.PHONY: build run clean docker docker-run

# Default values
MODEL_PATH ?= /models/model.gguf
PORT ?= 3000
N_THREADS ?= 0
N_BATCH ?= 256
CTX ?= 2048
N_PARALLEL ?= 4

# Build the application in release mode
build:
	cargo build --release
	cp target/release/mindforge-server-llm ..

# Run the application
run: build
	./mindforge-server-llm

# Clean build artifacts
clean:
	cargo clean

# Build Docker image
docker:
	docker build -t mindforge-server-llm-rust:latest .

# Run Docker container
docker-run: docker
	docker run -p $(PORT):$(PORT) \
		-v $(PWD)/../prompts:/prompts:ro \
		-v $(PWD)/../models:/models:ro \
		-e MODEL_PATH=$(MODEL_PATH) \
		-e PORT=$(PORT) \
		-e N_THREADS=$(N_THREADS) \
		-e N_BATCH=$(N_BATCH) \
		-e CTX=$(CTX) \
		-e N_PARALLEL=$(N_PARALLEL) \
		-e RUST_LOG=info \
		--name mindforge-rust \
		mindforge-server-llm-rust:latest

.PHONY: compose-up compose-down compose-pull systemd-install
compose-up:
	docker compose up --detach --build --remove-orphans

compose-down:
	docker compose down --remove-orphans

compose-pull:
	docker compose pull

# Benchmark server (requires wrk)
benchmark:
	@echo "Benchmarking with wrk..."
	wrk -t8 -c100 -d30s -s ./bench.lua http://localhost:$(PORT)/v1/chat/completions
