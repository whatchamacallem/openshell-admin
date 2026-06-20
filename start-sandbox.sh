#!/usr/bin/env bash
# start-sandbox.sh — start (boot) the "seafox" sandbox container.
#
#   ./start-sandbox.sh
#
# The OpenShell CLI has no start/stop verb; a sandbox's run state lives at the
# Docker container layer. This starts the container the gateway created for
# "seafox" (created by ./create-sandbox.sh). Idempotent: if it's already
# running, does nothing.
set -euo pipefail

NAME="seafox"
LABEL="openshell.ai/sandbox-name=${NAME}"

if ! command -v openshell >/dev/null 2>&1; then
    echo "error: openshell not on PATH." >&2
    exit 1
fi
if ! openshell sandbox get "${NAME}" >/dev/null 2>&1; then
    echo "error: sandbox '${NAME}' does not exist. Run ./create-sandbox.sh first." >&2
    exit 1
fi

cid="$(docker ps -aq --filter "label=${LABEL}" | head -1)"
if [[ -z "${cid}" ]]; then
    echo "error: no Docker container found for sandbox '${NAME}'." >&2
    exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "${cid}")" == "true" ]]; then
    echo "==> Sandbox '${NAME}' is already running."
    exit 0
fi

echo "==> Starting sandbox '${NAME}'..."
docker start "${cid}" >/dev/null
echo "==> Running: $(docker ps --filter id=${cid} --format '{{.Status}}')"
