#!/usr/bin/env bash
# install-openshell.sh — install OpenShell sandbox under WSL2.
#
#   ./install-openshell.sh
#
# Run as your NORMAL user (do not sudo this). The script escalates with sudo
# only where root is actually needed (the dpkg package layer), so it will
# prompt for your password. Everything else — the gateway (a *user* systemd
# service), config/state under ~/.config|.local — must run as you, which is why
# the script itself stays unprivileged.
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "error: do NOT run this as root/sudo." >&2
    echo "       Run it as your normal user: ./install-openshell.sh" >&2
    echo "       It will sudo internally for the parts that need root." >&2
    exit 1
fi

# Prime sudo up front so the password prompt happens once, here, not mid-run.
echo "==> This script needs sudo for the package install; prompting now."
sudo -v

echo "==> Installing OpenShell for $(id -un) (home ${HOME})"

# --- Prerequisite: Docker must be reachable -----------------------------------
echo "==> Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not found on PATH. Install Docker first." >&2
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "error: you cannot talk to the Docker daemon." >&2
    echo "       Add yourself to the 'docker' group (sudo usermod -aG docker $(id -un))" >&2
    echo "       and start a fresh login shell, then re-run." >&2
    exit 1
fi
echo "    Docker OK: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"

# --- Prerequisite: user systemd instance --------------------------------------
echo "==> Checking user systemd (for openshell-gateway.service)..."
if ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "error: no user systemd instance." >&2
    echo "       Ensure systemd is enabled in WSL (/etc/wsl.conf: [boot] systemd=true)." >&2
    exit 1
fi

# --- Install via the official installer ---------------------------------------
# The installer drops the dpkg package + user service unit. It invokes sudo
# itself for the package layer; sudo is already primed above so this is seamless.
echo "==> Running OpenShell installer..."
curl -fsSL https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh

# --- Enable + start the gateway (user service) --------------------------------
echo "==> Enabling and starting openshell-gateway.service (user scope)..."
systemctl --user daemon-reload
systemctl --user enable --now openshell-gateway.service

# Linger so the user service survives without an active login session.
echo "==> Enabling linger so the gateway survives logout..."
sudo loginctl enable-linger "$(id -un)" || true

# --- Report -------------------------------------------------------------------
echo "==> Done. Status:"
openshell --version || true
systemctl --user is-active openshell-gateway.service || true

cat <<EOF

Next steps:
  openshell sandbox create
  openshell sandbox list
Then we'll test the forkpty/devpts blocker before wiring up VS Code.
EOF
