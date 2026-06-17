# OpenShell as an Agent Sandbox

## Goal

Use the OpenShell sandbox as an isolated environment for an AI coding agent.

- **VS Code** is the client that talks to the sandbox (via Remote-SSH).
- **Claude Code** runs *inside* the sandbox container, not in WSL.
- An agent running inside the sandbox **cannot reach the WSL install** (no
  Windows/WSL files, no SSH credentials back out, no network path to WSL). The
  sandbox is the security boundary.

## Install

Installed via:

```bash
curl -fsSL https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
```

On Debian/Ubuntu this lays down (verified with v0.0.57):

- dpkg package `openshell` → binaries `/usr/bin/openshell`,
  `/usr/bin/openshell-gateway`, driver `/usr/libexec/openshell/openshell-driver-vm`
- user systemd service `openshell-gateway.service`
  (unit at `/usr/lib/systemd/user/openshell-gateway.service`)
- config/state under `~/.config/openshell`, `~/.local/share/openshell`,
  `~/.local/state/openshell`
- at runtime, Docker images (`ghcr.io/nvidia/.../sandboxes/base:latest`,
  `.../supervisor:*`), a container per sandbox, and a `openshell-docker` bridge network

### Full uninstall

```bash
systemctl --user stop openshell-gateway.service
systemctl --user disable openshell-gateway.service
docker rm -f $(docker ps -aq --filter name=openshell)
docker rmi -f <openshell images>; docker network rm openshell-docker
sudo dpkg --purge openshell && systemctl --user daemon-reload   # needs root
rm -rf ~/.config/openshell ~/.local/share/openshell ~/.local/state/openshell
# also clear the Host blocks from ~/.ssh/config and Windows %USERPROFILE%\.ssh\config
# and delete C:\Users\ajohn\openshell-proxy.bat
```

## Topology

```text
                 ProxyCommand (transport tunnel only)
Windows VS Code ──► openshell-proxy.bat ──► wsl.exe -d Ubuntu-24.04
                                              └─► /usr/bin/openshell ssh-proxy
                                                    --gateway-name openshell
                                                    --name <sandbox-name>
                                                       │
                                                       ▼
                                           OpenShell sandbox container
                                           (sandbox@<id>, home /sandbox,
                                            own subnet 10.200.0.x, separate)
                                            └─ VS Code server runs here
                                            └─ Claude Code agent runs here
```

The proxy is a **transport tunnel** for SSH traffic. It does not give the agent
process inside the container any access to WSL — see Isolation below.

## Three pieces of plumbing

### 1. Windows ssh config — used by VS Code (Windows app)

`C:\Users\ajohn\.ssh\config`

```text
Host openshell-<sandbox-name>
    User sandbox
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    GlobalKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 15
    ServerAliveCountMax 3
    ProxyCommand C:\Users\ajohn\openshell-proxy.bat
```

### 2. The proxy batch file — required by the Windows config

`C:\Users\ajohn\openshell-proxy.bat`

```bat
@wsl.exe -d Ubuntu-24.04 -- /usr/bin/openshell ssh-proxy --gateway-name openshell --name <sandbox-name>
```

It bridges a Windows SSH client into the WSL-resident `openshell` binary. The
leading `@` is essential: as a `ProxyCommand`, stdout must carry only the SSH
protocol stream. Without `@echo off`/`@`, cmd.exe echoes the command line to
stdout and corrupts the SSH banner exchange.

### 3. WSL ssh config — used only for connecting from inside WSL

`~/.ssh/config` (in WSL Ubuntu)

Same Host block, but calls the binary directly (no `.bat` needed, since we're
already in Linux):

```sh
    ProxyCommand /usr/bin/openshell ssh-proxy --gateway-name openshell --name <sandbox-name>
```

`openshell sandbox ssh-config <name>` prints the correct block. Keep both
configs and the `.bat` in sync with the current `--name` whenever the sandbox
is recreated (the name changes each time).

## Setup steps

1. **Connect VS Code to the sandbox.**
   Command Palette → *Remote-SSH: Connect to Host…* → `openshell-<sandbox-name>`.
   VS Code runs the `.bat` proxy and installs/uses its server inside the
   container (`/sandbox/.vscode-server`).

2. **Install Claude Code inside the sandbox.**
   In VS Code's integrated terminal (a shell inside the container):

   ```bash
   curl -fsSL https://claude.ai/install.sh | bash
   ```

   `curl`, `node`, `python3`/`uv`, `gcc`, and `git` are present in the sandbox.

3. **Run the agent from VS Code's terminal.**
   That Claude Code instance runs entirely inside the container and is subject
   to the isolation verified below.

## Isolation (verified from inside the sandbox, 2026-06-17)

All boundaries hold; no hardening was required.

- **Filesystem — isolated.** No `/mnt/c`, no Windows drive, no WSL home
  (`/home/t` does not exist). `/mnt` is permission-denied. No WSL/Windows/9p/
  drvfs mounts.
- **Credentials — isolated.** No `~/.ssh` keys or config. No forwarded SSH
  agent (`SSH_AUTH_SOCK` empty). No `openshell` binary inside the sandbox, so
  it cannot re-run the proxy back out.
- **Network — isolated.** Sandbox is on its own subnet (gateway 10.200.0.1).
  WSL has no interface on that network and runs no SSH server. The sandbox
  cannot open `:22` to its gateway (refused) and raw ping is blocked.

The only path between WSL and the sandbox is the `openshell ssh-proxy`
transport tunnel, which grants the in-container process no filesystem,
credential, or network access to WSL.

## KNOWN BLOCKER — VS Code terminal fails: `forkpty(3) failed` (2026-06-17)

Opening a terminal in the VS Code Remote-SSH session into the sandbox fails:

> The terminal process failed to launch: A native exception occurred during
> launch (forkpty(3) failed.).

### Root cause (confirmed, not theory)

The unprivileged `sandbox` user (uid 998) **cannot `forkpty`** inside the
OpenShell container — opening `/dev/ptmx` returns `EACCES` (errno 13), so no
pty can be allocated. The OpenShell **VM driver mounts devpts itself**, and its
setup does not give the unprivileged user a working ptmx:

```sh
# /usr/libexec/openshell/openshell-driver-vm
mount -t devpts devpts "$(root_path /dev/pts)" 2>/dev/null &
```

### What was tested (so you don't repeat it)

- **It is NOT the image or Docker.** A plain `docker run` of the *same* image
  (`ghcr.io/nvidia/.../sandboxes/base:latest`) as uid 998, with the default
  seccomp profile, runs `forkpty` successfully. Verified with a C `forkpty`
  test program — "forkpty OK".
- **It is NOT seccomp.** `seccomp=unconfined` made no difference; default
  profile works fine under plain `docker run`.
- **It is NOT a startup race.** A freshly created sandbox fails identically —
  the failure is deterministic. (An earlier delete+recreate on a race theory
  was wrong and only lost the old container's contents. Do not bother
  recreating as a fix.)
- **It is NOT simply group membership.** Adding `sandbox` to group `tty`
  (gid 5) lets a *fresh `docker exec`* open ptmx, but `forkpty` over SSH still
  fails — the SSH login and the driver's devpts instance are the difference.
- **Root inside the container CAN open ptmx**; the unprivileged user cannot.
  Host-side remount attempts (`mount -t devpts -o newinstance …`) failed
  because the original `/dev/pts` is busy and can't be cleanly unmounted from
  a running container.

### Conclusion / next attempt

This is an **OpenShell driver bug** in how it sets up devpts for the
unprivileged sandbox user. Avenues to try next time:

1. Check for a newer OpenShell release that fixes the driver's devpts mount.
2. Look for a sandbox-create option / policy / setting that controls the run
   user, tty-group membership, or devpts/privileged mode
   (`openshell settings`, `openshell policy`, `openshell sandbox create --help`).
3. If patching the driver: make it mount devpts with a proper `newinstance`
   instance whose `/dev/ptmx` is openable by the unprivileged user, OR run the
   agent user in group `tty` from container start (not added later).
4. Reproducer to attach to an upstream bug report: inside any sandbox, run a C
   program calling `forkpty()` as the `sandbox` user → `Permission denied`;
   the same program in a plain `docker run` of the same image → succeeds.

## Notes / caveats

- The arrangement where Claude Code runs in WSL and SSHes *into* the sandbox is
  backwards for the goal — that instance has the proxy + keys. Isolation only
  holds for an agent launched *inside* the container.
- Each `ssh ... 'cmd'` is a fresh non-interactive session starting at
  `/sandbox`; shell state (cwd, env, venv) does not persist between commands.
  Running the agent inside the container avoids this entirely.
