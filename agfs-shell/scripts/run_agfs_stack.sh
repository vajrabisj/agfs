#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_TAG="${AGFS_IMAGE_TAG:-agfs-server-plugins:latest}"
CONTAINER_NAME="${AGFS_CONTAINER_NAME:-agfs-server}"
HOST_PORT="${AGFS_PORT:-8080}"
DATA_DIR="${AGFS_DATA_DIR:-${REPO_ROOT}/data}"

if [[ -z "${PERPLEXITY_API_KEY:-}" ]]; then
  echo "PERPLEXITY_API_KEY is not set in the environment." >&2
  exit 1
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is not set in the environment." >&2
  exit 1
fi

mkdir -p "${DATA_DIR}"

echo "[1/3] Building custom AGFS image (${IMAGE_TAG})..."
docker build -f "${REPO_ROOT}/docker-image/Dockerfile" -t "${IMAGE_TAG}" "${REPO_ROOT}"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[info] Removing existing container ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "[2/3] Starting ${CONTAINER_NAME} on port ${HOST_PORT}..."
docker run --rm -it \
  --name "${CONTAINER_NAME}" \
  -p "${HOST_PORT}:8080" \
  -e PERPLEXITY_API_KEY="${PERPLEXITY_API_KEY}" \
  -e OPENAI_API_KEY="${OPENAI_API_KEY}" \
  -v "${DATA_DIR}:/data" \
  "${IMAGE_TAG}"

echo "[3/3] Container exited."
