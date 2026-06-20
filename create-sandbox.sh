#!/usr/bin/env bash
# create-sandbox.sh — create the "seafox" sandbox with the PTY-fix policy.
#
#   ./create-sandbox.sh
#
# Idempotent: if "seafox" already exists it does nothing. The sandbox is
# created with sea-fox-policy.yaml so interactive terminals (VS Code, tmux,
# forkpty) work, and from the seafox-sandbox image (base + packages.txt
# toolchain) built by ./build-image.sh — see openshell.md. The sandbox stays
# alive after creation.
set -euo pipefail

NAME="seafox"
IMAGE="seafox-sandbox:latest"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${DIR}/sea-fox-policy.yaml"

if ! command -v openshell >/dev/null 2>&1; then
    echo "error: openshell not on PATH. Run ./install-openshell.sh first." >&2
    exit 1
fi
if [[ ! -f "${POLICY}" ]]; then
    echo "error: policy file not found: ${POLICY}" >&2
    exit 1
fi

if openshell sandbox get "${NAME}" >/dev/null 2>&1; then
    echo "==> Sandbox '${NAME}' already exists; nothing to do."
    exit 0
fi

echo "==> Building sandbox image..."
"${DIR}/build-image.sh"

echo "==> Creating sandbox '${NAME}' with ${POLICY##*/} from ${IMAGE}..."
openshell sandbox create --name "${NAME}" --from "${IMAGE}" --policy "${POLICY}" --no-tty -- true

echo "==> Created. Status:"
openshell sandbox get "${NAME}" 2>/dev/null || true

echo "==> Installing Claude Code..."
"${DIR}/setup-claude.sh"

cat <<EOF

Next:
  ./start-sandbox.sh   # ensure it's running
  openshell sandbox connect ${NAME}
  ./stop-sandbox.sh    # shut it down (keeps it for later)
  ./delete-sandbox.sh  # remove it entirely
EOF
