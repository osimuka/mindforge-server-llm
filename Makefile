# ---- Config (override with env vars or on the CLI) ----
MODEL_FILE ?= Phi-3-mini-4k-instruct-Q4_K_S.gguf
MODEL_URL  ?= https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/$(MODEL_FILE)
REPO_URL   ?= https://github.com/osimuka/mindforge-server-llm.git

IMAGE_NAME ?= mindforge-server-llm:cpu
CONT_NAME  ?= mindforge-server-llm
LLAMA_PORT ?= 8080
API_PORT   ?= 3000
CTX        ?= 2048
N_THREADS  ?= 0
N_BATCH    ?= 256
N_PARALLEL ?= 1
PROMPTS_DIR ?= ./prompts

# ---- Local build & run ----
.PHONY: build run stop logs clean
build:
	cd rust-server && cargo build --release
	cp rust-server/target/release/mindforge-llm-server .

run: build
	./mindforge-llm-server

# Download a GGUF model into ./models (uses MODEL_FILE & MODEL_URL from top of file)
.PHONY: download-model install-model download-and-run
download-model:
	@echo "Downloading model: $(MODEL_FILE)"
	@mkdir -p $(CURDIR)/models
	@if [ -z "$(MODEL_FILE)" ]; then \
		echo "MODEL_FILE is not set"; exit 1; \
	fi
	@curl -L --fail -C - -o $(CURDIR)/models/$(MODEL_FILE) "$(MODEL_URL)"

# Install the downloaded model to the system default /models/model.gguf (requires sudo)
install-model: download-model
	@echo "Installing model to /models/model.gguf (requires sudo)"
	sudo mkdir -p /models
	sudo cp $(CURDIR)/models/$(MODEL_FILE) /models/model.gguf

# Build, download model, and run the server with MODEL_PATH pointed to the downloaded file
download-and-run: build download-model
	@echo "Running server with MODEL_PATH=$(CURDIR)/models/$(MODEL_FILE)"
	MODEL_PATH=$(CURDIR)/models/$(MODEL_FILE) ./mindforge-llm-server

stop:
	docker rm -f $(CONT_NAME) || true

logs:
	docker logs -f $(CONT_NAME)

clean:
	docker rm -f $(CONT_NAME) 2>/dev/null || true
	docker rmi $(IMAGE_NAME) 2>/dev/null || true

.PHONY: compose-up compose-down compose-pull systemd-install
compose-up:
	docker compose up --no-deps --build model-downloader

compose-down:
	docker compose down --remove-orphans

compose-pull:
	docker compose pull

systemd-install:
	sudo install -d /opt/mindforge-server-llm/deploy
	sudo cp deploy/mindforge.service /etc/systemd/system/mindforge.service
	sudo systemctl daemon-reload
	sudo systemctl enable --now mindforge.service
	sudo systemctl restart mindforge.service || true

# ---- Cloud-init rendering ----
.PHONY: cloud-init
cloud-init:
	@echo "Rendering cloud-init.yaml with:"
	@echo "  REPO_URL=$(REPO_URL)"
	@echo "  MODEL_FILE=$(MODEL_FILE)"
	@echo "  MODEL_URL=$(MODEL_URL)"
	@echo "  API_PORT=$(API_PORT)"
	@echo "  LLAMA_PORT=$(LLAMA_PORT)"
	sed -e 's|__REPO_URL__|$(REPO_URL)|g' \
		-e 's|__MODEL_FILE__|$(MODEL_FILE)|g' \
		-e 's|__MODEL_URL__|$(MODEL_URL)|g' \
		-e 's|__API_PORT__|$(API_PORT)|g' \
		-e 's|__LLAMA_PORT__|$(LLAMA_PORT)|g' \
		cloud-init.tmpl.yaml > cloud-init.yaml
	@echo "Wrote cloud-init.yaml"

# ---- OPTIONAL: Deploy with doctl (requires configured doctl + SSH key) ----
# Usage example:
#   make deploy-do NAME=llm-4gb REGION=lon1 SIZE=s-2vcpu-4gb SSH_KEY=your_ssh_key_id
NAME   ?= llm-4gb
REGION ?= lon1
SIZE   ?= s-2vcpu-4gb
SSH_KEY?=

.PHONY: deploy-do
deploy-do: cloud-init
ifndef SSH_KEY
	$(error Please set SSH_KEY=<your_digitalocean_ssh_key_id>)
endif
	doctl compute droplet create $(NAME) \
		--region $(REGION) --size $(SIZE) --image ubuntu-22-04-x64 \
		--user-data-file cloud-init.yaml --tag-names llm \
		--ssh-keys $(SSH_KEY) --wait
	@echo "Droplet $(NAME) requested. Open ports $(API_PORT) (API) and $(LLAMA_PORT) (LLM) in your DO firewall if needed."
