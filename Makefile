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
	docker build \
	  --platform linux/arm64 \
	  --build-arg MODEL_FILE=$(MODEL_FILE) \
	  --build-arg MODEL_URL=$(MODEL_URL) \
	  -t $(IMAGE_NAME) .

run: build
	docker rm -f $(CONT_NAME) 2>/dev/null || true
	docker run -d --name $(CONT_NAME) \
	  -p $(LLAMA_PORT):8080 \
	  -p $(API_PORT):3000 \
	  -v $(PROMPTS_DIR):/prompts \
	  -e PORT=$(API_PORT) \
	  -e CTX=$(CTX) \
	  -e N_THREADS=$(N_THREADS) \
	  -e N_BATCH=$(N_BATCH) \
	  -e N_PARALLEL=$(N_PARALLEL) \
	  --restart unless-stopped \
	  $(IMAGE_NAME)

stop:
	docker rm -f $(CONT_NAME) || true

logs:
	docker logs -f $(CONT_NAME)

clean:
	docker rm -f $(CONT_NAME) 2>/dev/null || true
	docker rmi $(IMAGE_NAME) 2>/dev/null || true

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
	@echo "Droplet $(NAME) requested. Open port $(PORT) in your DO firewall if needed."
