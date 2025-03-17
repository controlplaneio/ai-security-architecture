NAME ?= ai-sec-arch

CILIUM_VERSION ?= v1.16.7
CLUSTER_NAME := $(NAME)

ARCH := $(shell uname -m | sed 's/x86_64/amd64/')
OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')

export PATH := $(shell mise activate --shims):$(PATH)

.EXPORT_ALL_VARIABLES:

.PHONY: all
all: \
	setup \
	cluster-up \
	cilium-install \
	controls-install \
	chatbot-build \
	proxy-llm-guard-build \
	infra-up

.PHONY: down
down: cluster-down

.PHONY: setup
setup: ## Enforce pre-requisites
ifndef OPENAI_API_KEY
	$(error Set environment variable OPENAI_API_KEY before running `make all`)
endif

##@ Kind

.PHONY: cluster-up
cluster-up: ## Create the kind cluster
	kind create cluster --name $(CLUSTER_NAME) --config=kind-config.yaml

.PHONY: cluster-down
cluster-down: ## Delete the kind cluster
	-kind delete cluster --name $(CLUSTER_NAME)

##@ Infra

.PHONY: controls-install
controls-install:
	docker pull laiyer/llm-guard-api:latest
	kind load docker-image laiyer/llm-guard-api:latest -n $(CLUSTER_NAME)

.PHONY: cilium-install
cilium-install: ## Install Cilium
	helm repo add cilium https://helm.cilium.io/
	helm repo update
	docker pull quay.io/cilium/cilium:$(CILIUM_VERSION)
	kind load docker-image quay.io/cilium/cilium:$(CILIUM_VERSION) -n $(CLUSTER_NAME)
	helm install cilium cilium/cilium --version $(CILIUM_VERSION) \
		--namespace kube-system \
		--set image.pullPolicy=IfNotPresent \
		--set ipam.mode=kubernetes \
		--set envoy.enabled=false
	cilium status --wait

.PHONY: chatbot-build
chatbot-build: ## Build and load the chatbot container
	docker build -t proxy-chatbot:latest container/proxy-chatbot
	kind load docker-image proxy-chatbot:latest -n $(CLUSTER_NAME)

.PHONY: proxy-llm-guard-build
proxy-llm-guard-build: ## Build and load the proxy-llm-guard container
	docker build -t proxy-llm-guard:latest container/proxy-llm-guard
	kind load docker-image proxy-llm-guard:latest -n $(CLUSTER_NAME)

.PHONY: infra-up
infra-up:
	kubectl apply -f k8s/manifests/00-namespaces.yaml

	kubectl create secret generic app-chatbot-secret \
		--from-literal=PROXY_API_KEY="$(OPENAI_API_KEY)" \
		--namespace=app-chatbot

	kubectl apply -f "k8s/manifests/0[1-6]*.yaml"

	-while [ -z "$$(kubectl -n fw-prompt get po -l app=envoy-proxy -o jsonpath='{.items[0].metadata.generateName}')" -a -z "$$(kubectl -n app-chatbot get po -l app=app-chatbot -o jsonpath='{.items[0].metadata.generateName}')" -a -z "$$(kubectl -n fw-model get po -l app=envoy-proxy -o jsonpath='{.items[0].metadata.generateName}')" ]; do \
		sleep 2; \
		echo "Waiting for pods to be created."; \
	done

	kubectl wait --timeout=120s --for=condition=Ready pod -n fw-prompt -l app=envoy-proxy
	kubectl wait --timeout=120s --for=condition=Ready pod -n app-chatbot -l app=app-chatbot
	kubectl wait --timeout=120s --for=condition=Ready pod -n fw-model -l app=envoy-proxy
	kubectl wait --timeout=120s --for=condition=Ready pod -n ctrl-prompt -l app=llm-guard

.PHONY: test-prompt
test-prompt:
	curl -v -X POST -H "Content-Type: application/json" -d '{ "model": "proxy:gpt-4o", "messages": [{"role": "user", "content": "Say this is a test!"}], "temperature": 0.7 }' localhost:30080/v1/chat/completions ; echo

.PHONY: test-prompt-fail
test-prompt-fail:
	curl -v -X POST -H "Content-Type: application/json" -d '{ "model": "proxy:gpt-4o", "messages": [{"role": "user", "content": "I kill AIs"}], "temperature": 0.7 }' localhost:30080/v1/chat/completions ; echo

.PHONY: netpols-apply
netpols-apply:
	kubectl apply -f k8s/manifests/07-netpols.yaml

.PHONY: test
test:
	cd tests && bats hello-test.bats

##@ Tools

.PHONY: help
help: ## parse jobs and descriptions from this Makefile
	@grep -E '^[ a-zA-Z0-9_-]+:([^=]|$$)' $(MAKEFILE_LIST) \
	| grep -Ev '^help\b[[:space:]]*:' \
	| sort \
	| awk 'BEGIN {FS = ":.*?##"}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
