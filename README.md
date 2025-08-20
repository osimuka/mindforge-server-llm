# Local LLM Server (Rust)

Run any GGUF-quantized LLM on a small CPU-only server with a high-performance Rust API.

## Features

- Works with any `.gguf` file (Q4 fits in 4GB RAM)
- High-performance Rust implementation (handles 10,000+ requests/second)
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

## Docker Compose Environment

The Docker Compose deployment includes:

- **App Container**: Runs the LLM server with your GGUF model
- **Caddy Container**: Provides HTTPS and reverse proxy

### Environment Variables

You can customize the deployment with these environment variables:

```bash
# Image name and tag
export IMAGE_NAME=mindforge-server-llm:cpu

# Model configuration
export MODEL_FILE=Phi-3-mini-4k-instruct-Q4_K_S.gguf
export MODEL_URL=https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_S.gguf

# Performance tuning
export N_PARALLEL=1    # Number of parallel inference requests
export N_THREADS=0     # CPU threads (0 = auto)
export N_BATCH=256     # Batch size
export CTX=2048        # Context size
```

Edit the `deploy/Caddyfile` to configure your domain name before deployment.

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

## Deployment Options

### Cloud VM with cloud-init (DigitalOcean 4 GB RAM droplet)

1. Render cloud-init with your repo + model (defaults target a 4 GB box):

```bash
make cloud-init \
  REPO_URL=https://github.com/osimuka/mindforge-server-llm \
  MODEL_FILE=Phi-3-mini-4k-instruct-Q4_K_S.gguf \
  MODEL_URL=https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_S.gguf
```

### Direct Remote Deployment

Remote build & restart via SSH:

```bash
# Simple deployment (build on remote and restart)
./deploy-service.sh --host ubuntu@YOUR_SERVER_IP

# OR use Docker Compose with Caddy for HTTPS
./deploy-service.sh --host ubuntu@YOUR_SERVER_IP --compose
```

### Docker Compose Deployment

The repository includes a `docker-compose.yml` file that sets up:

1. The LLM server container
2. A Caddy reverse proxy for automatic HTTPS

To deploy with Docker Compose:

```bash
# Start all services locally
make compose-up

# Stop all services
make compose-down
```

The Caddy configuration automatically obtains SSL certificates for your domain.

### SystemD Service Installation

For persistent service on Linux servers:

```bash
# Install as a systemd service (will start on boot)
sudo make systemd-install
```
