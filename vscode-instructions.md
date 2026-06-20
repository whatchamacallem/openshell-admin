# Connect VS Code to the `seafox` sandbox

Follow these steps in order. They assume **VS Code runs on Windows** and OpenShell
runs in **WSL (Ubuntu-24.04)**, which is your setup. Claude Code will run *inside*
the sandbox once you're connected — that container is the security boundary.

Concrete values for your machine (already verified):

| Thing | Value |
|---|---|
| WSL distro | `Ubuntu-24.04` |
| `openshell` binary (in WSL) | `/usr/bin/openshell` |
| Gateway name | `openshell` |
| SSH host alias | `openshell-seafox` |
| Sandbox user | `sandbox` |

Replace `ajohn` below with your Windows username if different (your home is
`C:\Users\ajohn\`).

---

## Step 0 — One-time: install the VS Code Remote-SSH extension

In VS Code (Windows): open Extensions (`Ctrl+Shift+X`), search **Remote - SSH**
(publisher: Microsoft), install it. Skip if already installed.

---

## Step 1 — Make sure `seafox` is running (in WSL)

Open a WSL terminal in `~/openshell-admin` and run:

```bash
./create-sandbox.sh   # no-op if it already exists
./start-sandbox.sh    # boots it; no-op if already running
```

Confirm it's `Ready`:

```bash
openshell sandbox get seafox
```

You want `Phase: Ready`. Leave this terminal open.

---

## Step 2 — One-time: create the Windows proxy batch file

VS Code on Windows reaches the sandbox by shelling into WSL. Create the file
`C:\Users\ajohn\openshell-proxy.bat` with this command:

```powershell
Set-Content -Path "$env:USERPROFILE\openshell-proxy.bat" -Encoding ascii -Value '@wsl.exe -d Ubuntu-24.04 -- /usr/bin/openshell ssh-proxy --gateway-name openshell --name seafox'
```

It must contain this:

```bat
@wsl.exe -d Ubuntu-24.04 -- /usr/bin/openshell ssh-proxy --gateway-name openshell --name seafox
```

The leading `@` is required — it stops cmd.exe from echoing the command and
corrupting the SSH stream.


---

## Step 3 — One-time: add the SSH host block on Windows

Open (create if missing) `C:\Users\ajohn\.ssh\config` and add:

```text
Host openshell-seafox
    User sandbox
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    GlobalKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 15
    ServerAliveCountMax 3
    ProxyCommand C:\Users\ajohn\openshell-proxy.bat
```

Quick way (Windows PowerShell):

```powershell
$cfg = "$env:USERPROFILE\.ssh\config"
New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
Add-Content -Path $cfg -Value @"

Host openshell-seafox
    User sandbox
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    GlobalKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 15
    ServerAliveCountMax 3
    ProxyCommand $env:USERPROFILE\openshell-proxy.bat
"@
```

---

## Step 4 — Connect VS Code to the sandbox

In VS Code (Windows):

1. `Ctrl+Shift+P` → **Remote-SSH: Connect to Host…**
2. Pick **`openshell-seafox`**.
3. A new window opens; if asked for platform, choose **Linux**.
4. Wait for "VS Code Server" to install inside the sandbox
   (`/sandbox/.vscode-server`). First connect takes ~30–60s.

You're connected when the bottom-left green badge reads
**SSH: openshell-seafox**.

---

## Step 5 — Open a folder and a terminal

1. **File → Open Folder…** → `/sandbox` → OK.
2. **Terminal → New Terminal** (`` Ctrl+` ``).

The terminal must open without `forkpty(3) failed` — `seafox` was created with
the PTY-fix policy, so this works. The C/C++ toolchain (clang, cmake, ninja,
gdb, ctags, …) is baked into the image — see *Installing packages* below.
Verify:

```bash
tty           # -> /dev/pts/0
whoami        # -> sandbox
pwd           # -> /sandbox
```

---

## Step 6 — Run Claude Code inside the sandbox

`./create-sandbox.sh` already installed Claude Code (via `setup-claude.sh`) and
put `claude` on PATH. In that integrated terminal (running **inside** the
container), just start it:

```bash
claude
```

If `claude` isn't found, the sandbox predates this automation — run
`./setup-claude.sh` from `~/openshell-admin` in WSL.

This Claude Code instance runs entirely inside `seafox`. It has no access to
your WSL or Windows files, SSH keys, or network — the sandbox is the boundary.

Outbound network is restricted to an allowlist (see Egress below). `seafox`
allows GitHub, Anthropic, `claude.ai` (installer), and `claude.com`
(Claude Code runtime); other hosts return `403 CONNECT tunnel failed`.

### Optional — the Claude Code VS Code extension

The extension is separate from the CLI above. When connected over Remote-SSH,
VS Code shows *"disabled… install in 'SSH: openshell-seafox'"* — it must be
installed into the **remote** server, not Windows. In the connected window:
`Ctrl+Shift+X` → **Claude Code** → **Install in SSH: openshell-seafox** →
reload. The Marketplace is on the egress allowlist, so the download succeeds.

---

## Egress

Outbound traffic goes through a deny-by-default proxy. `seafox` allows
GitHub (`git clone`/pull/push), Anthropic (Claude), `claude.ai` /
`**.claude.ai` (`install.sh` + `downloads.claude.ai` binary), and `claude.com` /
`**.claude.com` (`platform.claude.com`, Claude Code's runtime API), and the
VS Code Marketplace (`marketplace.visualstudio.com` + CDN, for installing
extensions into the remote server). Anything else fails with `CONNECT tunnel
failed, response 403`.

To allow another host (e.g. a package registry), add a line to
`sea-fox-policy.yaml` under `network_policies.egress.endpoints` — list both the
apex and the wildcard:

```yaml
      - { host: "pypi.org", ports: [443] }
      - { host: "**.pypi.org", ports: [443] }
```

Then recreate (network policy is set at create time only):

```bash
./delete-sandbox.sh && ./create-sandbox.sh
```

See [openshell.md](openshell.md) → *Egress policy* for the wildcard rules.

---

## Installing packages

You run as the unprivileged `sandbox` user (no root, no `sudo`), and `/usr` is
read-only — so `apt install` **cannot** run inside the sandbox. apt packages are
baked into the image at build time instead.

To add an apt package: add it to [packages.txt](packages.txt), then recreate:

```bash
./delete-sandbox.sh && ./create-sandbox.sh && ./start-sandbox.sh
```

`./create-sandbox.sh` rebuilds the image ([build-image.sh](build-image.sh) /
[Dockerfile](Dockerfile)) before creating, so the new packages land in the
sandbox. The first build is slow.

Language packages don't need this — `pip install --user`, `uv`, and local
`npm install` work as the `sandbox` user, but their registry hosts must be on
the egress allowlist (see *Egress*).

---

## When you're done

- **Keep it for later:** in WSL, `./stop-sandbox.sh` (shuts the container down;
  start again with `./start-sandbox.sh`, then reconnect via Step 4).
- **Throw it away:** in WSL, `./delete-sandbox.sh` (removes it entirely; you'd
  re-run `./create-sandbox.sh` next time — the host alias stays the same, so the
  Windows config from Steps 2–3 keeps working).

---

## Troubleshooting

- **`forkpty(3) failed` in the terminal** → `seafox` was created without the PTY
  policy. In WSL: `./delete-sandbox.sh && ./create-sandbox.sh` (the create script
  always applies `sea-fox-policy.yaml`).
- **`403 CONNECT tunnel failed` on `git clone`/`curl`** → the host isn't on the
  egress allowlist. Add it to `sea-fox-policy.yaml` and recreate (see *Egress*).
- **VS Code can't connect / proxy errors** → in WSL, `openshell sandbox get
  seafox` must say `Ready`; if not, `./start-sandbox.sh`. Confirm the gateway is
  up: `openshell status` (expect `Connected`).
- **"command not found" mid-connect** → check the `.bat` is exactly the one line
  in Step 2 (leading `@`, distro `Ubuntu-24.04`, path `/usr/bin/openshell`).
- **Connecting from inside WSL instead of Windows VS Code** → run
  `openshell sandbox connect seafox --editor vscode`; it writes the WSL-side SSH
  config and launches automatically. (Steps 2–3 are only needed for Windows VS
  Code.)
