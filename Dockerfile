FROM rust:1.75-slim as builder

WORKDIR /app
COPY rust-server .

# Install build dependencies
RUN apt-get update && \
    apt-get install -y build-essential cmake && \
    rm -rf /var/lib/apt/lists/*

# Build the application
RUN cargo build --release

# Create runtime image
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from the builder
COPY --from=builder /app/target/release/mindforge-server-llm /app/mindforge-server-llm

# Create directories for models and prompts
RUN mkdir -p /models /prompts

# Runtime settings
ENV MODEL_PATH=/models/model.gguf
ENV CTX=2048
ENV PORT=3000
ENV N_THREADS=0
ENV N_BATCH=256
ENV N_PARALLEL=1

# Expose port
EXPOSE 3000

# Run the application
CMD ["/app/mindforge-server-llm"]
