# Mindforge Rust Server

A high-performance Rust implementation of the LLM server designed to handle 10,000+ requests per second.

## Key Features

- Direct llama.cpp integration via Rust FFI (no HTTP overhead)
- Async request handling with Actix Web
- Request rate limiting and backpressure handling
- Optimized for high concurrency workloads
- Same API interface as the Python version

## Building the Server

```bash
cd rust-server
cargo build --release
```

## Configuration

The server uses the same environment variables as the Python version:

```
MODEL_PATH=/models/model.gguf  # Path to GGUF model file
PORT=3000                      # HTTP port to listen on
N_THREADS=0                    # CPU threads (0 = auto)
N_BATCH=256                    # Batch size for inference
CTX=2048                       # Context size
N_PARALLEL=1                   # Parallel inference instances
```

## Performance Optimizations

The Rust implementation includes several optimizations:

1. **Concurrent Processing**: Uses Tokio for async I/O and Rayon for parallel processing
2. **Memory Efficiency**: Zero-copy parsing and response generation
3. **Connection Pooling**: Maintains connection pools for high throughput
4. **Backpressure Handling**: Gracefully handles overload situations
5. **Direct FFI**: No intermediate HTTP calls to llama.cpp

## Benchmarking

To benchmark the server:

```bash
# Install wrk HTTP benchmarking tool
brew install wrk  # macOS
apt install wrk   # Ubuntu/Debian

# Run benchmark (adjust threads/connections based on your hardware)
wrk -t12 -c400 -d30s -s bench.lua http://localhost:3000/v1/chat/completions
```

Example `bench.lua` script:

```lua
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"
wrk.body = [[{
  "model": "phi3",
  "messages": [
    {"role": "user", "content": "Hello"}
  ],
  "temperature": 0.7,
  "max_tokens": 10
}]]
```
