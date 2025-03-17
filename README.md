# AI Reference Architecture Demo

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

> [!NOTE]
> This project is built to demo some of the components of the [FINOS AI Governance Framework](https://github.com/finos/ai-readiness).


## Demo

In this demo, placeholder Envoy proxies have been introduced for the prompt firewall and model firewall, which log requests and responses. The role of the AI-enabled application is played by [aichat](https://github.com/sigoden/aichat), which forwards on requests to OpenAI via the model firewall.

Security contexts for the proxies and `aichat` have been hardened, and the `fw-prompt`, `app-chatbot` and `fw-model` namespaces have Pod Security Standards enforced at the Restricted level. Cilium is used as the CNI, and network policies have been set up so that inbound traffic to `aichat` must come from the `fw-prompt` namespace, and egress traffic must go to the `fw-model` namespace.

1. Set the `OPENAI_API_KEY` environment variable:

```bash
export OPENAI_API_KEY=<Paste Your API Key Here>
```

2. **Install** and **activate** [mise](https://mise.jdx.dev/) following the instructions for your workstation [here](https://mise.jdx.dev/getting-started.html).

3. Use `mise` to install the **required** CLI tools:

    ```sh
    mise trust
    mise install
    mise run deps
    ```

4. Spin up the infrastructure:

```bash
make all
```

5. Watch the logs for evidence of startup, for example llm-guard needs to pull models from Hugging Face:

Depending on the first-run conditions, you may need to run `make test-prompt` until the environment is prepared.

```bash
$ kubectl logs -n ctrl-prompt -l app=llm-guard
{"model": "Model(path='unitary/unbiased-toxic-roberta', subfolder='', revision='36295dd80b422
dc49f40052021430dae76241adc', onnx_path='ProtectAI/unbiased-toxic-roberta-onnx', onnx_revision='34480fa958f6657ad835c345808475755b6974a7', onn
x_subfolder='', onnx_filename='model.onnx', kwargs={}, pipeline_kwargs={'batch_size': 1, 'device': device(type='cpu'), 'padding': 'max_length'
, 'top_k': None, 'function_to_apply': 'sigmoid', 'return_token_type_ids': False, 'max_length': 256, 'truncation': True}, tokenizer_kwargs={})"
, "device": "device(type='cpu')", "event": "Initialized classification ONNX model", "level": "debug", "timestamp": "2024-10-29T07:16:18.009892
Z"}
```

6. After the models are ready:

```bash
make netpols-apply
```

7. Send an example passing request:

```bash
make test-prompt
```

> [!NOTE]
> This step should complete successfully. Monitor the logs to check for model reconcilliation activity

8. Send an example failing request:

```bash
make test-prompt-fail
```

This step should fail with something like `{"is_valid":false,"scanners":{"BanTopics":1.0}}`

9. This infrastructure is now ready for red-teaming!

```bash
python3 -m garak  --model_type rest -G garak-rest.json --probes dan.DanInTheWildMini
```

## Teardown

```bash
make down
```
