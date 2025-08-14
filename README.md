# Local LLM Server (CPU)

Run any GGUF-quantized LLM on a small CPU-only server with llama.cpp’s OpenAI-compatible API.

## Features

- Works with any `.gguf` file (Q4 fits in 4GB RAM)
- CPU-only; runs on small cloud VMs or locally
- Exposes `/v1/chat/completions` endpoint

## Build the image — this downloads the Q4 model inside the container

```bash
docker build \
  --build-arg MODEL_FILE=Phi-3-mini-4k-instruct-Q4_K_S.gguf \
  --build-arg MODEL_URL=https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_S.gguf \
  -t mindforge-server-llm:cpu .

```

## Deploy to DigitalOcean (4 GB RAM droplet)

1. Render cloud-init with your repo + model (defaults target a 4 GB box):

```bash
make cloud-init \
  REPO_URL=https://github.com/osimuka/mindforge-server-llm \
  MODEL_FILE=Phi-3-mini-4k-instruct-Q4_K_S.gguf \
  MODEL_URL=https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_S.gguf
```

## Run the server

```bash
make run
```
