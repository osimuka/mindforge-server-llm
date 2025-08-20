#!/usr/bin/env bash
set -euo pipefail

# If N_THREADS is unset or 0, default to number of CPUs
if [ "${N_THREADS:-0}" = "0" ]; then
  N_THREADS=$(nproc)
fi

# Compute MODEL_PATH at runtime from MODEL_FILE if not already set
if [ -n "${MODEL_FILE:-}" ]; then
  MODEL_PATH=/models/${MODEL_FILE}
else
  MODEL_PATH=${MODEL_PATH:-/models/model.gguf}
fi
echo "Using MODEL_FILE=${MODEL_FILE:-<unset>} MODEL_PATH=${MODEL_PATH}"

if [ -n "${SYSTEM_PROMPT_PATH:-}" ] && [ -f "$SYSTEM_PROMPT_PATH" ]; then
  echo "Loading system prompt from $SYSTEM_PROMPT_PATH"
  SYSTEM_PROMPT=$(cat "$SYSTEM_PROMPT_PATH")
else
  SYSTEM_PROMPT=""
fi

# Informational startup
echo "Starting llama server with absolute path..."

MODEL_OK=0
# Start the llama server in the background if possible
if [ -x /app/llama-server ]; then
  if [ -f "$MODEL_PATH" ]; then
    echo "Starting llama server with model $MODEL_PATH"
    /app/llama-server \
      -m "$MODEL_PATH" \
      -c "$CTX" \
      -b "$N_BATCH" \
      -t "$N_THREADS" \
      --parallel "$N_PARALLEL" \
      --mlock \
      --host 0.0.0.0 \
      --port 8080 &
    LLAMA_PID=$!
    MODEL_OK=1
  else
    echo "Model file $MODEL_PATH not found — skipping LLM server startup. FastAPI will run in degraded mode."
  fi
else
  echo "LLM server executable not found at /app/llama-server — running FastAPI only (degraded mode)."
fi

# If LLM server started, wait for it to be healthy; otherwise continue
if [ "$MODEL_OK" -eq 1 ]; then
  echo "Waiting for LLM server to start..."
  for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null; then
      echo "LLM server is up!"
      break
    fi
    if [ $i -eq 30 ]; then
      echo "Timed out waiting for LLM server — continuing with FastAPI in degraded mode"
      MODEL_OK=0
      break
    fi
    sleep 1
  done
fi

# Start the FastAPI service with optimized settings
echo "Starting FastAPI service..."
export PYTHONOPTIMIZE=2
export UVICORN_WORKERS=${UVICORN_WORKERS:-$(nproc)}
export UVICORN_LOOP=uvloop
export UVICORN_HTTP=httptools

if [ "$MODEL_OK" -eq 1 ]; then
  echo "FastAPI will proxy to local LLM server on port 8080"
else
  echo "FastAPI running in degraded mode: upstream LLM unavailable"
fi

exec python3 -m uvicorn server:app --host 0.0.0.0 --port 3000 --workers $UVICORN_WORKERS
