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

## SOLVED — VS Code terminal `forkpty(3) failed` was a Landlock policy gap (2026-06-17)

**Symptom:** any in-sandbox PTY allocation by the unprivileged `sandbox` user
(uid 998) — VS Code's terminal, `tmux`, a C `forkpty`, Python `pty.fork()` —
failed with `EACCES` (errno 13) / "out of pty devices", while the SSH *login*
shell worked.

**Root cause:** the supervisor applies a **default-deny Landlock** ruleset built
**only** from `filesystem_policy.read_only/read_write` (+ workdir), in
`openshell-supervisor-process/src/sandbox/linux/landlock.rs`. The default policy
never lists `/dev/pts`, so a uid-998 process that opens `/dev/ptmx` to allocate
a *new* pty is denied. Not the VM driver (gateway runs `driver=docker`), not
devpts perms (`/dev/ptmx` is 777, but Landlock overrides DAC), not seccomp
(default-Allow, returns EPERM not EACCES). The login shell works because **root**
opens its pty *before* Landlock; VS Code's server calls `forkpty` itself, *after*
Landlock → denied.

**Fix:** add `/dev/pts` to `read_write` in the sandbox policy, then create with
`--policy`. `filesystem_policy` is static — must be set at create time. List the
`/dev/pts` *directory*, not `/dev/ptmx` (a symlink: the supervisor chowns
read_write paths and refuses to chown symlinks). See
[`sea-fox-policy.yaml`](sea-fox-policy.yaml).

```bash
openshell sandbox create --name dev --policy ./sea-fox-policy.yaml --editor vscode
```

**Verified (2026-06-17):** default policy → `forkpty FAILED (errno 13)` /
`OSError: out of pty devices`; with `/dev/pts` in read_write → `forkpty OK
(uid=998)`, interactive `tty` → `/dev/pts/0`, Python `pty.fork()` succeeds.

Upstream-worthy: the **default** sandbox policy should include `/dev/pts` so
terminals work out of the box. See
[`BUG-REPORT-devpts-forkpty.md`](BUG-REPORT-devpts-forkpty.md).

## Egress policy

The sandbox routes all outbound traffic through a proxy that defaults to
**deny**. A sandbox with no `network_policies` blocks every CONNECT
(`fatal: ... CONNECT tunnel failed, response 403`). To allow egress, add a
`network_policies` block to the sandbox policy and create with `--policy`
(network policy is set at create time only — there is no hot-update verb).

Rules (enforced by the supervisor at startup; a bad value crash-loops the
container):

- Each entry matches **both** an endpoint (host + port) **and** a binary
  (resolved `/proc/<pid>/exe`). `binaries: [{ path: "/**" }]` allows any binary.
- No `*`/`**` bare host (rejected: "matches all hosts"); no TLD wildcard
  (`*.com`). Widest legal host is `**.<domain>` (recursive wildcard, ≥3 labels).
- `**.<domain>` matches **subdomains only** — the glob delimiter is `.`, so it
  does **not** match the apex. List the apex (`github.com`) **and** the wildcard
  (`**.github.com`) to cover both.
- No port wildcard; enumerate ports (e.g. `[80, 443]`).

[`sea-fox-policy.yaml`](sea-fox-policy.yaml) allows GitHub (apex + subdomains),
Anthropic, `claude.ai`, and `claude.com` (Claude Code). Add a
`{ host: "**.<domain>", ports: [443] }` line per host
family the agent needs (e.g. `pypi.org`, `registry.npmjs.org`).

```bash
openshell sandbox exec -n <name> -- git clone https://github.com/owner/repo.git
```

## Sandbox image / apt packages

The sandbox runs as unprivileged `sandbox` (uid 998, no root/`sudo`) with `/usr`
read-only, so `apt install` cannot run inside it. apt packages are baked into a
custom image at build time instead: [`Dockerfile`](Dockerfile) is
`FROM ghcr.io/nvidia/openshell-community/sandboxes/base:latest` + the toolchain
in [`packages.txt`](packages.txt). [`build-image.sh`](build-image.sh) builds it
into the local Docker daemon as `seafox-sandbox:latest`; `create-sandbox.sh`
rebuilds then creates with `--from "${IMAGE}"`.

To add a package: edit [`packages.txt`](packages.txt), then
`./delete-sandbox.sh && ./create-sandbox.sh`. The image build runs in WSL's
Docker (unrestricted network), not under the sandbox egress policy.

## Notes / caveats

- The arrangement where Claude Code runs in WSL and SSHes *into* the sandbox is
  backwards for the goal — that instance has the proxy + keys. Isolation only
  holds for an agent launched *inside* the container.
- Each `ssh ... 'cmd'` is a fresh non-interactive session starting at
  `/sandbox`; shell state (cwd, env, venv) does not persist between commands.
  Running the agent inside the container avoids this entirely.
