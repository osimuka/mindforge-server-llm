FROM rust:1.70-slim as builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y \
    pkg-config \
    libssl-dev \
    cmake \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy manifests
COPY Cargo.toml ./

# Create dummy src/main.rs to build dependencies
RUN mkdir -p src && \
    echo "fn main() {}" > src/main.rs && \
    cargo build --release && \
    rm -rf src

# Copy source code
COPY src ./src

# Build the application
RUN cargo build --release

# Runtime stage
FROM debian:bullseye-slim

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    libssl1.1 \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /models /prompts

# Copy the binary from builder
COPY --from=builder /app/target/release/mindforge-llm-server /usr/local/bin/

# Set environment variables
ENV RUST_LOG=info
ENV PORT=3000
ENV MODEL_PATH=/models/model.gguf
ENV CTX=2048
ENV N_THREADS=0
ENV N_BATCH=256
ENV N_PARALLEL=1

# Expose port for API
EXPOSE 3000

# Set working directory
WORKDIR /app

# Set command
CMD ["mindforge-llm-server"]
