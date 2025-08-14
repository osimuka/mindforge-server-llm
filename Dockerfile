FROM --platform=linux/arm64 ghcr.io/ggerganov/llama.cpp:full

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

# Entrypoint setup
EXPOSE 8080
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
