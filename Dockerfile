FROM ghcr.io/ggerganov/llama.cpp:full AS base

# Install Python and dependencies
RUN apt-get update && \
    apt-get install -y python3 python3-pip curl && \
    rm -rf /var/lib/apt/lists/*

# Copy and install Python requirements
COPY requirements.txt /app/requirements.txt
RUN pip3 install -r /app/requirements.txt

# Default model settings (override with build args)
ARG MODEL_FILE=model.gguf
ARG MODEL_URL=

# Runtime settings (override with env vars at docker run)
ENV MODEL_PATH=/models/${MODEL_FILE}
ENV CTX=2048
ENV PORT=8080
ENV N_THREADS=0
ENV N_BATCH=256
ENV N_PARALLEL=1

# Download model if MODEL_URL is set
RUN mkdir -p /models && \
    if [ -n "${MODEL_URL}" ]; then \
    echo "Downloading ${MODEL_URL}" && \
    curl -L -o "${MODEL_PATH}" "${MODEL_URL}"; \
    else \
    echo "No MODEL_URL provided — mount your model.gguf at /models"; \
    fi

# Copy application files
COPY server.py /app/server.py
COPY entrypoint.sh /app/entrypoint.sh
COPY ./prompts /prompts

# Setup permissions and working directory
RUN chmod +x /app/entrypoint.sh
WORKDIR /app

# Expose port for both llama server and FastAPI
EXPOSE 8080 3000

ENTRYPOINT ["/app/entrypoint.sh"]
