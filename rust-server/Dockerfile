# Builder stage: use official Rust image and cache dependencies
FROM rust:latest as builder

# Install build dependencies (include clang/libclang for bindgen)
RUN apt-get update && \
    apt-get install -y \
    pkg-config \
    libssl-dev \
    cmake \
    build-essential \
    git \
    clang \
    libclang-dev \
    llvm-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy manifests (including Cargo.lock if present) to leverage layer caching
COPY Cargo.toml Cargo.lock ./

# Create minimal src to give cargo a target and cache dependencies
RUN mkdir -p src && \
    echo "fn main() { println!(\"dep-cache\"); }" > src/main.rs && \
    cargo build --release && \
    rm -rf src

# Copy the real source tree and build final release
COPY src ./src

# Ensure stale prebuilt deps for this binary are removed
RUN rm -f ./target/release/deps/mindforge-llm-server* || true

RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

# Runtime dependencies
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    openssl \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /models /prompts

# Copy the binary from builder
COPY --from=builder /app/target/release/mindforge-llm-server /usr/local/bin/

ENV RUST_LOG=info
ENV PORT=3000
ENV MODEL_PATH=/models/model.gguf
ENV CTX=2048
ENV N_THREADS=0
ENV N_BATCH=256
ENV N_PARALLEL=1

EXPOSE 3000

WORKDIR /app

CMD ["mindforge-llm-server"]
