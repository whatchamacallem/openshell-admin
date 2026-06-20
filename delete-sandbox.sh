#!/usr/bin/env bash
# delete-sandbox.sh — delete the "seafox" sandbox entirely.
#
#   ./delete-sandbox.sh
#
# Idempotent: safe to run when "seafox" does not exist.
set -euo pipefail

NAME="seafox"

if ! command -v openshell >/dev/null 2>&1; then
    echo "error: openshell not on PATH." >&2
    exit 1
fi

if ! openshell sandbox get "${NAME}" >/dev/null 2>&1; then
    echo "==> Sandbox '${NAME}' does not exist; nothing to delete."
    exit 0
fi

echo "==> Deleting sandbox '${NAME}'..."
openshell sandbox delete "${NAME}"
echo "==> Deleted."
