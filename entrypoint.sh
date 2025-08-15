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

# Start the llama server in the background
if [ -x /app/llama-server ]; then
  /app/llama-server \
    -m "$MODEL_PATH" \
    -c "$CTX" \
    -b "$N_BATCH" \
    -t "$N_THREADS" \
    --parallel "$N_PARALLEL" \
    --host 0.0.0.0 \
    --port 8080 &
else
  echo "ERROR: Cannot find llama server executable at /app/llama-server"
  echo "Looking for server executables anywhere on the system:"
  find / -name "*server*" -type f -executable 2>/dev/null || echo "No server executables found"
  exit 1
fi

# Wait for llama server to start
sleep 5

# Start the FastAPI service
echo "Starting FastAPI service..."
exec python3 /app/server.py
