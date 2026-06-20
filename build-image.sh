#!/usr/bin/env bash
# build-image.sh — build the "seafox" sandbox image (base + packages.txt).
#
#   ./build-image.sh
#
# Builds Dockerfile into the local Docker daemon as ${IMAGE}. The toolchain in
# packages.txt is installed at build time (as root), so it needs no sudo and
# survives sandbox recreates. ./create-sandbox.sh points the sandbox at this
# image via `--from`. Re-run after editing packages.txt.
set -euo pipefail

IMAGE="seafox-sandbox:latest"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not on PATH." >&2
    exit 1
fi

echo "==> Building ${IMAGE} from ${DIR}/Dockerfile..."
docker build -t "${IMAGE}" -f "${DIR}/Dockerfile" "${DIR}"
echo "==> Built ${IMAGE}."
