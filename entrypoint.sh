#!/usr/bin/env bash
set -euo pipefail

if [ "$N_THREADS" = "0" ]; then
  N_THREADS=$(nproc)
fi

if [ -n "${SYSTEM_PROMPT_PATH:-}" ] && [ -f "$SYSTEM_PROMPT_PATH" ]; then
  echo "Loading system prompt from $SYSTEM_PROMPT_PATH"
  SYSTEM_PROMPT=$(cat "$SYSTEM_PROMPT_PATH")
else
  SYSTEM_PROMPT=""
fi

echo "Starting llama server with absolute path..."

# Use the absolute path to the server executable 
if [ -x /app/llama-server ]; then
  exec /app/llama-server \
    -m "$MODEL_PATH" \
    -c "$CTX" \
    -b "$N_BATCH" \
    -t "$N_THREADS" \
    --parallel "$N_PARALLEL" \
    --host 0.0.0.0 \
    --port "$PORT"
else
  echo "ERROR: Cannot find llama server executable at /app/llama-server"
  echo "Looking for server executables anywhere on the system:"
  find / -name "*server*" -type f -executable 2>/dev/null || echo "No server executables found"
  exit 1
fi
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3",
    "messages": [
      {"role": "user", "content": "Hello, how are you today?"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'