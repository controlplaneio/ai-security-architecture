# AI Security Reference Architecture Demo

## Prerequisites

The following client tools are needed to run this demo:

- [Docker](https://www.docker.com/)
- [Kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)
- [Helm](https://helm.sh/)

An [OpenAI](https://platform.openai.com/) account and API Key are needed, with a Project with some credits.

## Architecture

The following diagram shows the demo architecture.

```mermaid
graph LR;
 client([client])-. port forward .->fw-prompt-svc[Service: fw-prompt];

 subgraph cluster

   subgraph "fw-prompt"
     fw-prompt-svc-->fw-prompt-deploy["Deployment: envoy-proxy(fw-prompt)"];
   end

   subgraph "ctrl-prompt"
     fw-prompt-deploy-->ctrl-prompt-svc[Service: ctrl-prompt];
     ctrl-prompt-svc-->ctrl-prompt-deploy["Deployment: envoy-proxy (ctrl-prompt)"];
     ctrl-prompt-deploy-->fw-prompt-deploy
   end

   subgraph "app-chatbot"
     fw-prompt-deploy-->app-chatbot-svc[Service: app-chatbot];
     app-chatbot-svc-->app-chatbot-deploy["Deployment: app-chatbot (app-chatbot)"];
   end

   subgraph "app-chatbot-vectordb"
     app-chatbot-deploy-->app-chatbot-vectordb-svc[Service: app-chatbot-vectordb];
     app-chatbot-vectordb-svc-->app-chatbot-vectordb-deploy["Deployment: app-chatbot-vectordb (app-chatbot)"];
     app-chatbot-vectordb-deploy-->app-chatbot-deploy
   end

   subgraph "app-chatbot-confluence"
     app-chatbot-deploy-->app-chatbot-confluence-svc[Service: app-chatbot-confluence];
     app-chatbot-confluence-svc-->app-chatbot-confluence-deploy["Deployment: app-chatbot-confluence (app-chatbot)"];
     app-chatbot-confluence-deploy-->app-chatbot-deploy
   end

   subgraph "fw-model"
     app-chatbot-deploy-->fw-model-svc[Service: fw-model];
     fw-model-svc-->envoy-proxy-fw-model["Deployment: envoy-proxy (fw-model)"];
   end

   subgraph "ctrl-model"
     envoy-proxy-fw-model-->ctrl-model-svc[Service: ctrl-model];
     ctrl-model-svc-->ctrl-model-deploy["Deployment: envoy-proxy (ctrl-model)"];
     ctrl-model-deploy-->envoy-proxy-fw-model
   end

 end

  envoy-proxy-fw-model-->external-inference["External Inference"];

 classDef plain fill:#ddd,stroke:#fff,stroke-width:4px,color:#000;
  classDef k8s fill:#326ce5,stroke:#fff,stroke-width:4px,color:#fff;
  classDef k8s-controls fill:#000,stroke:#fff,stroke-width:4px,color:#fff;
  classDef k8s-data fill:#964500,stroke:#fff,stroke-width:4px,color:#fff;
 classDef cluster fill:#fff,stroke:#bbb,stroke-width:2px,color:#326ce5;
  class ingress,app-chatbot-svc,app-chatbot-deploy,envoy-proxy-fw-model,fw-model-svc,fw-model-deploy,envoy-proxy-fw-prompt,fw-prompt-svc,fw-prompt-deploy k8s;
  class ctrl-model-deploy,ctrl-model-svc,ctrl-model,ctrl-prompt-deploy,ctrl-prompt-svc,ctrl-prompt k8s-controls;
  class app-chatbot-confluence-svc,app-chatbot-confluence-deploy,app-chatbot-vectordb-svc,app-chatbot-vectordb-deploy k8s-data;
 class client plain;
 class cluster cluster;
```

## Demo

In this demo, placeholder Envoy proxies and an echo server (which takes the place of a prompt firewall via Envoy [external authorization](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)) have been introduced for the prompt firewall and model firewall, which log requests and responses. The role of the AI-enabled application is played by [aichat](https://github.com/sigoden/aichat), which forwards on requests to OpenAI via the model firewall.

Security contexts for the proxies and `aichat` have been hardened, and the `fw-prompt`, `app-chatbot` and `fw-model` namespaces have Pod Security Standards enforced at the Restricted level. Cilium is used as the CNI, and network policies have been set up so that inbound traffic to `aichat` must come from the `fw-prompt` namespace, and egress traffic must go to the `fw-model` namespace.

Set the `OPENAI_API_KEY` environment variable:

```bash
export OPENAI_API_KEY=<Paste Your API Key Here>
```

Spin up the infrastructure:

```bash
make all
```

Set up port forwarding to the prompt-firewall:

```bash
make port-forward
```

Send an example request:

```bash
make example-prompt
```

Run the example Bats test:

```bash
make test
```

## Teardown

```bash
make down
```
