#!/usr/bin/env bash
# stop-sandbox.sh — stop (shut down) the "seafox" sandbox container.
#
#   ./stop-sandbox.sh
#
# The OpenShell CLI has no start/stop verb; a sandbox's run state lives at the
# Docker container layer. This stops the container without deleting the
# sandbox — restart it later with ./start-sandbox.sh. Idempotent: if it's
# already stopped, does nothing.
set -euo pipefail

NAME="seafox"
LABEL="openshell.ai/sandbox-name=${NAME}"

if ! command -v openshell >/dev/null 2>&1; then
    echo "error: openshell not on PATH." >&2
    exit 1
fi

cid="$(docker ps -aq --filter "label=${LABEL}" | head -1)"
if [[ -z "${cid}" ]]; then
    echo "==> No Docker container for sandbox '${NAME}'; nothing to stop."
    exit 0
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "${cid}")" != "true" ]]; then
    echo "==> Sandbox '${NAME}' is already stopped."
    exit 0
fi

echo "==> Stopping sandbox '${NAME}'..."
docker stop "${cid}" >/dev/null
echo "==> Stopped: $(docker ps -a --filter id=${cid} --format '{{.Status}}')"
