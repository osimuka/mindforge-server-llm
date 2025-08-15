# Local LLM Server (CPU)

Run any GGUF-quantized LLM on a small CPU-only server with llama.cpp's OpenAI-compatible API.

## Features

- Works with any `.gguf` file (Q4 fits in 4GB RAM)
- CPU-only; runs on small cloud VMs or locally
- Exposes `/v1/chat/completions` endpoint
- Supports dynamic prompt switching via API
- Mount custom prompt templates without rebuilding

## Build and Run

```bash
# Build and run with default settings
make run

# Run with a specific default prompt
make run DEFAULT_PROMPT=coding_assistant
```

## API Endpoints

The server exposes the following endpoints:

- **Main API**: `http://localhost:8000/v1/chat/completions`
- **List available prompts**: `http://localhost:8000/prompts`
- **Health check**: `http://localhost:8000/health`

### Using Dynamic Prompts

You can switch between different system prompts without restarting the server:

```bash
# Use the coding assistant prompt for this request
curl -X POST "http://localhost:8000/v1/chat/completions?prompt=coding_assistant" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3",
    "messages": [
      {"role": "user", "content": "Write a function that reverses a string"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'

# Use the creative writer prompt for this request
curl -X POST "http://localhost:8000/v1/chat/completions?prompt=creative_writer" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3",
    "messages": [
      {"role": "user", "content": "Write a short story about a magical forest"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

### Available Prompt Templates

The server comes with these prompt templates:

- `default` - General-purpose helpful assistant
- `coding_assistant` - Programming and technical help
- `creative_writer` - Creative writing and storytelling

You can add your own prompts by:

1. Creating a text file in the `prompts/` directory (e.g., `prompts/my_custom_prompt.txt`)
2. Using it via the API: `/v1/chat/completions?prompt=my_custom_prompt`

## Adding Custom Prompts

The server mounts the local `prompts/` directory, so you can add new prompt files without rebuilding:

1. Create a new text file in the `prompts/` directory:

   ```bash
   echo "You are a helpful math tutor." > prompts/math_tutor.txt
   ```

2. Use it immediately via the API:
   ```bash
   curl -X POST "http://localhost:8000/v1/chat/completions?prompt=math_tutor" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "phi3",
       "messages": [
         {"role": "user", "content": "Help me understand quadratic equations"}
       ],
       "temperature": 0.7,
       "max_tokens": 100
     }'
   ```

## Deploy to DigitalOcean (4 GB RAM droplet)

1. Render cloud-init with your repo + model (defaults target a 4 GB box):

```bash
make cloud-init \
  REPO_URL=https://github.com/osimuka/mindforge-server-llm \
  MODEL_FILE=Phi-3-mini-4k-instruct-Q4_K_S.gguf \
  MODEL_URL=https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_S.gguf
```
