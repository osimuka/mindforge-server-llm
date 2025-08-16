
#!/usr/bin/env bash
set -euo pipefail

# deploy-service.sh
# Build and deploy the image, optionally push to a registry, and restart the container
# Usage examples:
#  ./deploy-service.sh --host ubuntu@1.2.3.4            # build on remote and restart
#  ./deploy-service.sh --host ubuntu@1.2.3.4 --registry ghcr.io/you/repo:tag  # build locally, push, pull on remote
#  ./deploy-service.sh --local                           # build and restart locally

### Defaults (can be overridden via env or flags)
MODEL_FILE=${MODEL_FILE:-Phi-3-mini-4k-instruct-Q4_K_S.gguf}
MODEL_URL=${MODEL_URL:-https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/${MODEL_FILE}}
IMAGE_NAME=${IMAGE_NAME:-mindforge-server-llm:cpu}
CONT_NAME=${CONT_NAME:-mindforge-server-llm}
REPO_URL=${REPO_URL:-https://github.com/osimuka/mindforge-server-llm.git}

API_PORT=${API_PORT:-3000}
LLAMA_PORT=${LLAMA_PORT:-8080}
CTX=${CTX:-2048}
N_THREADS=${N_THREADS:-0}
N_BATCH=${N_BATCH:-256}
N_PARALLEL=${N_PARALLEL:-1}
PROMPTS_DIR=${PROMPTS_DIR:-./prompts}

# runtime
REMOTE_HOST=""
SSH_USER="ubuntu"
SSH_KEY=""
BUILD_LOCAL=false
HELP=false
GIT_TOKEN=""
COMPOSE_REMOTE=false

print_help(){
	cat <<EOF
Usage: $0 [options]

Options:
	--host user@host   Deploy to remote host (ssh). If omitted and --local not set, script will require --host.
	--ssh-key PATH     SSH private key for remote access (optional).
	--local            Build and restart on local machine instead of remote.
	--help             Show this help.

Examples:
	$0 --host ubuntu@1.2.3.4
	$0 --host ubuntu@1.2.3.4 --registry ghcr.io/me/mindforge:latest
	$0 --local
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--host)
			REMOTE_HOST="$2"; shift 2;;
		--ssh-key)
			SSH_KEY="$2"; shift 2;;
		--registry)
				echo "Registry/push workflow removed: this repo is public and we build locally or remotely. Ignore --registry."; shift 1;;
		--local)
			BUILD_LOCAL=true; shift 1;;
		--git-token)
			GIT_TOKEN="$2"; shift 2;;
		--compose)
			COMPOSE_REMOTE=true; shift 1;;
		--help|-h)
			print_help; exit 0;;
		*)
			echo "Unknown arg: $1"; print_help; exit 1;;
	esac
done

ssh_cmd(){
	local host="$1"
	if [[ -n "$SSH_KEY" ]]; then
		ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$host" -- "$2"
	else
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$host" -- "$2"
	fi
}

run_remote_build_and_restart(){
	local host="$1"
	echo "[remote] Updating repo on remote and building image: $host"
	ssh_cmd "$host" "mkdir -p /opt && cd /opt && if [ -d mindforge-server-llm ]; then cd mindforge-server-llm && git fetch --all && git reset --hard origin/main || true; else git clone ${REPO_URL} mindforge-server-llm; fi"

	ssh_cmd "$host" "cd /opt/mindforge-server-llm && docker build --build-arg MODEL_FILE='${MODEL_FILE}' --build-arg MODEL_URL='${MODEL_URL}' -t ${IMAGE_NAME} ."

	ssh_cmd "$host" "docker rm -f ${CONT_NAME} 2>/dev/null || true && docker run -d --name ${CONT_NAME} -p 127.0.0.1:${LLAMA_PORT}:8080 -p 127.0.0.1:${API_PORT}:3000 -v /opt/mindforge-server-llm/prompts:/prompts -e PORT=${API_PORT} -e CTX=${CTX} -e N_THREADS=${N_THREADS} -e N_BATCH=${N_BATCH} -e N_PARALLEL=${N_PARALLEL} --restart unless-stopped ${IMAGE_NAME}"

	echo "[remote] Waiting briefly and checking container status..."
	ssh_cmd "$host" "sleep 2 && docker ps --filter name=${CONT_NAME} --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
}

run_remote_compose_and_restart(){
	local host="$1"
	echo "[remote] Deploying via docker compose on ${host}"
	if [[ -n "${GIT_TOKEN}" ]]; then
		# use token for cloning private repo
		AUTH_URL=$(echo "${REPO_URL}" | sed -E "s#https://#https://${GIT_TOKEN}@#")
		ssh_cmd "$host" "mkdir -p /opt && cd /opt && if [ -d mindforge-server-llm ]; then cd mindforge-server-llm && git fetch --all && git reset --hard origin/main || true; else git clone ${AUTH_URL} mindforge-server-llm; fi"
	else
		ssh_cmd "$host" "mkdir -p /opt && cd /opt && if [ -d mindforge-server-llm ]; then cd mindforge-server-llm && git fetch --all && git reset --hard origin/main || true; else git clone ${REPO_URL} mindforge-server-llm; fi"
	fi

	ssh_cmd "$host" "cd /opt/mindforge-server-llm && docker compose up -d --build"
	echo "[remote] Waiting briefly and checking containers..."
	ssh_cmd "$host" "sleep 2 && docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
}

# registry/push workflow removed — builds are local or remote

run_local_build_and_restart(){
	echo "[local] Building image ${IMAGE_NAME} locally"
	docker build --build-arg MODEL_FILE="${MODEL_FILE}" --build-arg MODEL_URL="${MODEL_URL}" -t "${IMAGE_NAME}" .

	if [[ -n "${REGISTRY_IMAGE}" ]]; then
		echo "--registry ignored: building local image only"
	fi

	echo "[local] Restarting container ${CONT_NAME}"
	docker rm -f "${CONT_NAME}" 2>/dev/null || true
	docker run -d --name "${CONT_NAME}" -p ${LLAMA_PORT}:8080 -p ${API_PORT}:3000 -v "${PROMPTS_DIR}:/prompts" -e PORT=${API_PORT} -e CTX=${CTX} -e N_THREADS=${N_THREADS} -e N_BATCH=${N_BATCH} -e N_PARALLEL=${N_PARALLEL} --restart unless-stopped ${REGISTRY_IMAGE:-${IMAGE_NAME}}
	docker ps --filter name=${CONT_NAME} --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
}

health_check_remote(){
	local host="$1"
	echo "[remote] Health-checking API on ${host} (localhost: ${API_PORT})"
	ssh_cmd "$host" "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:${API_PORT}/ || true"
}

health_check_local(){
	echo "[local] Health-checking API on localhost:${API_PORT}"
	curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:${API_PORT}/ || true
}

### Main flow
if [[ "$BUILD_LOCAL" = true && -z "$REMOTE_HOST" ]]; then
	run_local_build_and_restart
	health_check_local
	exit 0
fi



if [[ -n "$REMOTE_HOST" ]]; then
	# remote build (no registry) or remote compose
	if [[ "$COMPOSE_REMOTE" = true ]]; then
		run_remote_compose_and_restart "$REMOTE_HOST"
		health_check_remote "$REMOTE_HOST"
		exit 0
	fi
	run_remote_build_and_restart "$REMOTE_HOST"
	health_check_remote "$REMOTE_HOST"
	exit 0
fi

echo "No action taken. Use --host user@host or --local. Use --help for usage."
exit 1
