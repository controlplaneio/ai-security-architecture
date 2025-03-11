NAME ?= ai-sec-arch
KIND_VERSION ?= 0.27.0
HELM_VERSION ?= 3.17.0
KUBECTL_VERSION ?= 1.32.2
CILIUM_VERSION ?= v1.16.7
CILIUM_CLI_VERSION ?= v0.18.2

CLUSTER_NAME := $(NAME)

BIN_DIR ?= bin

OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m | sed 's/x86_64/amd64/')

.EXPORT_ALL_VARIABLES:

.PHONY: all
all: \
	setup cluster-up \
	cilium-install controls-install \
	chatbot-build proxy-llm-guard-build \
	infra-up

.PHONY: down
down: stop-port-forwarding cluster-down

.PHONY: setup
setup:
	@mkdir -p $(BIN_DIR)
	@echo "Ensured directory exists: $(BIN_DIR)"

##@ Kind

.PHONY: cluster-up
cluster-up: kind ## Create the kind cluster
	$(KIND) create cluster --name $(CLUSTER_NAME) --config=kind-config.yaml

.PHONY: cluster-down
cluster-down: kind ## Delete the kind cluster
	-$(KIND) delete cluster --name $(CLUSTER_NAME)

##@ Infra

.PHONY: controls-install
controls-install:
	docker pull laiyer/llm-guard-api:latest
	$(KIND) load docker-image laiyer/llm-guard-api:latest -n $(CLUSTER_NAME)

.PHONY: cilium-install
cilium-install: helm cilium
	$(HELM) repo add cilium https://helm.cilium.io/
	$(HELM) repo update
	docker pull quay.io/cilium/cilium:$(CILIUM_VERSION)
	$(KIND) load docker-image quay.io/cilium/cilium:$(CILIUM_VERSION) -n $(CLUSTER_NAME)
	$(HELM) install cilium cilium/cilium --version $(CILIUM_VERSION) \
   --namespace kube-system \
   --set image.pullPolicy=IfNotPresent \
   --set ipam.mode=kubernetes \
	 --set envoy.enabled=false
	$(CILIUM) status --wait

.PHONY: chatbot-build
chatbot-build:
	docker build -t proxy-chatbot:latest .
	$(KIND) load docker-image proxy-chatbot:latest -n $(CLUSTER_NAME)

.PHONY: proxy-llm-guard-build
proxy-llm-guard-build:
	cd container/proxy-llm-guard && \
		docker build -t proxy-llm-guard:latest .
	$(KIND) load docker-image proxy-llm-guard:latest -n $(CLUSTER_NAME)

.PHONY: infra-up
infra-up: kubectl
ifndef OPENAI_API_KEY
	$(error OPENAI_API_KEY is not set. Please set it before running the infra-up command)
endif

	$(KUBECTL) apply -f k8s/manifests/00-namespaces.yaml

	$(KUBECTL) create secret generic app-chatbot-secret \
		--from-literal=PROXY_API_KEY="$(OPENAI_API_KEY)" \
		--namespace=app-chatbot

	kubectl apply -f "k8s/manifests/*.yaml"

	-while [ -z "$$($(KUBECTL) -n fw-prompt get po -l app=envoy-proxy -o jsonpath='{.items[0].metadata.generateName}')" -a -z "$$(kubectl -n app-chatbot get po -l app=app-chatbot -o jsonpath='{.items[0].metadata.generateName}')" -a -z "$$(kubectl -n fw-model get po -l app=envoy-proxy -o jsonpath='{.items[0].metadata.generateName}')" ]; do \
		sleep 2; \
   	echo "Waiting for pods to be created."; \
	done

	$(KUBECTL) wait --timeout=120s --for=condition=Ready pod -n fw-prompt -l app=envoy-proxy
	$(KUBECTL) wait --timeout=120s --for=condition=Ready pod -n app-chatbot -l app=app-chatbot
	$(KUBECTL) wait --timeout=120s --for=condition=Ready pod -n fw-model -l app=envoy-proxy

.PHONY: port-forward
port-forward:
	$(KUBECTL) -n fw-prompt port-forward svc/fw-prompt 8080:80 &
	$(KUBECTL) -n ctrl-prompt port-forward svc/echoserver 8081:80 &
	$(KUBECTL) -n ctrl-prompt port-forward svc/llm-guard 8082:80 &

.PHONY: stop-port-forwarding
stop-port-forwarding:
	-lsof -ti:8080 | xargs --no-run-if-empty kill -9 || true
	-lsof -ti:8081 | xargs --no-run-if-empty kill -9 || true
	-lsof -ti:8082 | xargs --no-run-if-empty kill -9 || true

.PHONY: test-prompt
test-prompt:
	curl -v -X POST -H "Content-Type: application/json" -d '{ "model": "proxy:gpt-4o", "messages": [{"role": "user", "content": "Say this is a test!"}], "temperature": 0.7 }' localhost:8080/v1/chat/completions ; echo

.PHONY: test-prompt-fail
test-prompt-fail:
	curl -v -X POST -H "Content-Type: application/json" -d '{ "model": "proxy:gpt-4o", "messages": [{"role": "user", "content": "I kill AIs"}], "temperature": 0.7 }' localhost:8080/v1/chat/completions ; echo

.PHONY: netpols-apply
netpols-apply:
	kubectl apply -f k8s/manifests/04-netpols.yaml

.PHONY: test
test:
	cd tests && bats hello-test.bats

##@ Tools

KIND = $(shell pwd)/$(BIN_DIR)/kind
KUBECTL = $(shell pwd)/$(BIN_DIR)/kubectl
HELM = $(shell pwd)/$(BIN_DIR)/helm
CILIUM = $(shell pwd)/$(BIN_DIR)/cilium

.PHONY: helm
helm: ## Download helm
ifeq (,$(wildcard $(HELM)))
	@{ \
		curl -sLO https://get.helm.sh/helm-v$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz; \
		tar -C $(BIN_DIR) --strip-components=1 -xzf helm-v$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz $(OS)-$(ARCH)/helm;\
		chmod +x $(HELM); \
		rm helm-v$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz; \
	}
endif

.PHONY: kind
KIND = $(shell pwd)/bin/kind
kind: ## Download kind if required
ifeq (,$(wildcard $(KIND)))
ifeq (,$(shell which kind 2> /dev/null))
	@{ \
		mkdir -p $(dir $(KIND)); \
		curl -sSLo $(KIND) https://kind.sigs.k8s.io/dl/v$(KIND_VERSION)/kind-$(OS)-$(ARCH); \
		chmod +x $(KIND); \
	}
else
KIND = $(shell which kind)
endif
endif

.PHONY: kubectl
kubectl: ## Download kubectl
ifeq (,$(wildcard $(KUBECTL)))
	@{ \
		curl -sLo $(KUBECTL) https://dl.k8s.io/release/v$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl ; \
		chmod +x $(KUBECTL); \
	}
endif

.PHONY: cilium
cilium: ##Download Cilium CLI
ifeq (,$(wildcard $(CILIUM)))
	@{ \
		curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-${OS}-${ARCH}.tar.gz; \
		tar -C $(BIN_DIR) -xzvf cilium-${OS}-${ARCH}.tar.gz;\
		chmod +x $(CILIUM); \
		rm cilium-$(OS)-$(ARCH).tar.gz; \
	}
endif

.PHONY: help
help: ## parse jobs and descriptions from this Makefile
	@grep -E '^[ a-zA-Z0-9_-]+:([^=]|$$)' $(MAKEFILE_LIST) \
	| grep -Ev '^help\b[[:space:]]*:' \
	| sort \
	| awk 'BEGIN {FS = ":.*?##"}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
