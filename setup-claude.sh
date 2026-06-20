#!/usr/bin/env bash
# setup-claude.sh — install Claude Code inside the "seafox" sandbox.
#
#   ./setup-claude.sh
#
# Idempotent: skips the install if claude is already present. Runs the official
# installer inside the container and adds ~/.local/bin to the sandbox user's
# PATH (the installer drops the binary there but does not wire up PATH). Setup
# lives in the container, so it must be re-run after ./create-sandbox.sh.
set -euo pipefail

NAME="seafox"

if ! command -v openshell >/dev/null 2>&1; then
    echo "error: openshell not on PATH. Run ./install-openshell.sh first." >&2
    exit 1
fi
if ! openshell sandbox get "${NAME}" >/dev/null 2>&1; then
    echo "error: sandbox '${NAME}' does not exist. Run ./create-sandbox.sh first." >&2
    exit 1
fi

echo "==> Configuring git identity..."
openshell sandbox exec -n "${NAME}" -- git config --global user.name "A Johnston"
openshell sandbox exec -n "${NAME}" -- git config --global user.email "ajohnston54637@gmail.com"

if openshell sandbox exec -n "${NAME}" -- bash -lc 'command -v claude' >/dev/null 2>&1; then
    echo "==> Claude Code already installed in '${NAME}'; nothing else to do."
    exit 0
fi

echo "==> Installing Claude Code in '${NAME}'..."
openshell sandbox exec -n "${NAME}" -- bash -c 'curl -fsSL https://claude.ai/install.sh | bash'

echo "==> Adding ~/.local/bin to PATH..."
openshell sandbox exec -n "${NAME}" -- bash -c \
    'grep -q "/.local/bin" ~/.bashrc 2>/dev/null || echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.bashrc'

echo "==> Done. Version:"
openshell sandbox exec -n "${NAME}" -- bash -lc 'claude --version' || true
