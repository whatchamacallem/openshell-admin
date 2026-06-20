#!/usr/bin/env bash
# uninstall-openshell.sh — fully remove OpenShell under WSL2.
#
#   ./uninstall-openshell.sh
#
# Run as your NORMAL user (do not sudo this). The script escalates with sudo
# only for the dpkg purge, so it will prompt for your password. Idempotent:
# safe to re-run. Does NOT touch the Windows-side files (.ssh\config blocks,
# openshell-proxy.bat) — remove those by hand (see note at the end).
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "error: do NOT run this as root/sudo." >&2
    echo "       Run it as your normal user: ./uninstall-openshell.sh" >&2
    echo "       It will sudo internally where root is needed." >&2
    exit 1
fi

echo "==> This script needs sudo for the package purge; prompting now."
sudo -v

echo "==> Uninstalling OpenShell for $(id -un) (home ${HOME})"

# --- Stop + disable the gateway service ---------------------------------------
echo "==> Stopping/disabling openshell-gateway.service..."
systemctl --user stop openshell-gateway.service 2>/dev/null || true
systemctl --user disable openshell-gateway.service 2>/dev/null || true

# --- Remove runtime Docker artifacts (containers, images, network) ------------
echo "==> Removing OpenShell containers..."
ids=$(docker ps -aq --filter name=openshell 2>/dev/null) && [ -n "$ids" ] && docker rm -f $ids || true

echo "==> Removing OpenShell images..."
imgs=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" 2>/dev/null \
        | grep -iE "openshell|nvidia/.*sandbox" | awk "{print \$2}" | sort -u)
[ -n "$imgs" ] && docker rmi -f $imgs || true

echo "==> Removing openshell-docker bridge network..."
docker network rm openshell-docker 2>/dev/null || true

# --- Purge the dpkg package (needs root) --------------------------------------
echo "==> Purging dpkg package 'openshell'..."
if dpkg -l openshell >/dev/null 2>&1; then
    sudo dpkg --purge openshell || sudo apt-get remove --purge -y openshell || true
else
    echo "    (package not installed)"
fi

# --- Remove leftover user config/state ----------------------------------------
echo "==> Removing user config/state dirs..."
rm -rf "${HOME}/.config/openshell" \
       "${HOME}/.local/share/openshell" \
       "${HOME}/.local/state/openshell"

# --- Reload systemd so the removed unit is forgotten --------------------------
systemctl --user daemon-reload 2>/dev/null || true

echo "==> Verifying removal:"
command -v openshell >/dev/null 2>&1 && echo "    WARNING: 'openshell' still on PATH" || echo "    openshell binary gone"
dpkg -l openshell >/dev/null 2>&1 && echo "    WARNING: dpkg pkg still present" || echo "    dpkg package gone"

cat <<'EOF'

==> WSL side cleaned. Remaining MANUAL steps (outside WSL):
  - Remove the "Host openshell-*" block from the WSL ~/.ssh/config
  - On Windows: remove the same Host block from %USERPROFILE%\.ssh\config
  - On Windows: delete C:\Users\<you>\openshell-proxy.bat
EOF
