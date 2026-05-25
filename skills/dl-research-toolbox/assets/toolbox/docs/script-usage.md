# Script Usage Guide

This guide covers the scripts you normally use after installing the toolbox on a new machine. Commands assume you are in the toolbox directory.

## One-command setup

Use the top-level wrapper on a fresh machine. It detects `./mihomo.yaml` or `~/mihomo.yaml` automatically, or accepts an explicit path. It runs network-first setup and then `scripts/doctor.sh`.

```bash
bash install.sh --mihomo-yaml /path/to/mihomo.yaml
```

Common variants:

```bash
bash install.sh --mihomo-yaml /path/to/mihomo.yaml --no-bootstrap
bash install.sh --mihomo-yaml /path/to/mihomo.yaml --replace-running
bash install.sh --mihomo-yaml /path/to/mihomo.yaml --skip-python-tools
bash install.sh --mihomo-yaml /path/to/mihomo.yaml --dry-run
```

## Network-first setup

Use this on a fresh machine. It installs mihomo first, imports your local YAML file, configures mihomo autostart by default, enables proxy variables for the script process, installs Codex CLI, then runs full bootstrap through the proxy. Use a local YAML file for cold-start migration because a subscription URL may be blocked before the proxy is running.

```bash
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml
```

Common variants:

```bash
# Replace an old mihomo process already holding the port.
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml --replace-running

# Configure proxy and Codex CLI only; skip full bootstrap.
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml --no-bootstrap

# Disable persistent startup only when this machine should not auto-start the proxy.
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml --no-autostart

# URL import is explicit and should only be used after direct network access works.
bash scripts/network-first-setup.sh --url 'https://example.com/sub.yaml'
```

## Web UI over SSH forwarding

Recommended local-side helper. Run this from a local copy of the repository:

```bash
bash scripts/web-tunnel.sh
```

On the first run, the helper asks for the SSH target, SSH port, and remote repository directory, then saves them to `~/.config/dl-research-toolbox/web-tunnel.env`. Later runs use the same command and do not need the SSH target again.

For non-interactive setup, save the profile explicitly:

```bash
bash scripts/web-tunnel.sh --target user@server --ssh-port 22 --remote-dir '~/dl-research-toolbox' --save-profile
```

The helper opens the SSH tunnel and starts the remote Web UI in one command. Open the tokenized local URL printed by the remote command.

Manual fallback on the server:

```bash
cd ~/dl-research-toolbox
bash scripts/web-ui.sh --port 8765
```

Manual tunnel from your local machine:

```bash
ssh -N -L 8765:127.0.0.1:8765 user@server
```

The UI can start/stop/restart mihomo, run proxy checks, run doctor checks, and inspect autostart status. It binds to `127.0.0.1` by default and does not require HTTP tunneling.

## Proxy session commands

```bash
# Start mihomo for this machine.
bash scripts/mihomo-start.sh

# Export http_proxy/https_proxy/all_proxy for the current shell.
source scripts/proxy-on.sh

# Remove proxy variables from the current shell.
source scripts/proxy-off.sh

# Stop the mihomo process started by the toolbox.
bash scripts/mihomo-stop.sh
```

Use this after a fresh SSH login if you only need the shell to use the existing proxy:

```bash
source scripts/proxy-on.sh
```

## mihomo config import

Import a local Clash/Mihomo YAML file. This is the recommended path for a new machine before the proxy is available:

```bash
bash scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml --replace-running
```

Interactive import prompts for a local YAML path:

```bash
bash scripts/mihomo-import-subscription.sh
```

URL import remains available only when direct network access already works:

```bash
bash scripts/mihomo-import-subscription.sh --url 'https://example.com/sub.yaml'
```

The real generated config lives in `~/.config/mihomo/config.yaml`. Do not copy that file into this repository.

## Autostart

Immediate start is handled by `mihomo-start.sh`. Persistent startup is handled by `mihomo-autostart.sh`. `network-first-setup.sh` installs persistent startup by default after a successful YAML import.

Default automatic selection:

```bash
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
bash scripts/mihomo-autostart.sh status
```

Preferred true boot autostart on a normal systemd machine:

```bash
bash scripts/mihomo-autostart.sh install --mode system
bash scripts/mihomo-autostart.sh status
```

Systemd user service, useful when you do not want a system service:

```bash
bash scripts/mihomo-autostart.sh install --mode user --enable-linger
bash scripts/mihomo-autostart.sh status
```

Fallback for containers or SSH images without systemd user services:

```bash
bash scripts/mihomo-autostart.sh install --mode profile
bash scripts/mihomo-autostart.sh status
```

Remove all autostart entries:

```bash
bash scripts/mihomo-autostart.sh uninstall
```

## Validation

Unified post-install check. It sources `scripts/proxy-on.sh` by default:

```bash
bash scripts/doctor.sh
```

Quick proxy-only check:

```bash
bash scripts/doctor.sh --quick
```

The full doctor runs `check-machine.sh`, `mihomo-status.sh --strict --test-proxy`, and `verify-proxy-deep.sh`. The deep check covers proxy environment variables, curl to GitHub/Hugging Face/PyPI/npm registry, Git over HTTPS, `npm view`, Codex CLI, `uv`, and selected Python research-tool imports.

## Codex CLI

Install or repair Codex CLI after proxy is available:

```bash
bash scripts/install-codex-cli.sh
codex --version
```

The script ensures a modern Node.js is installed, handles Ubuntu Node 12 conflicts, reinstalls broken Codex CLI packages, and persists `~/.local/bin` into shell profiles.

On Linux, Codex also expects the OS package manager's `bubblewrap` package so `bwrap` is available on PATH. The installer installs it on apt-based systems and then runs:

```bash
bash scripts/check-codex-sandbox.sh
```

The check distinguishes two cases:

- `bwrap is not on PATH`: install `bubblewrap` with the OS package manager, for example `apt-get update && apt-get install -y bubblewrap`.
- `bwrap: Creating new namespace failed: Operation not permitted`: `bubblewrap` is installed, but the host/container policy blocks namespace creation. The PATH prerequisite is fixed; full sandbox execution requires container runtime or host permission changes.

Reference: [OpenAI Codex sandbox prerequisites](https://developers.openai.com/codex/concepts/sandboxing#prerequisites).

## Bootstrap

Inspect the install plan:

```bash
bash scripts/bootstrap.sh --dry-run
```

Install common tools and the trimmed Python research venv:

```bash
bash scripts/bootstrap.sh
```

Skip Python tools if you only need system CLI tools:

```bash
INSTALL_PYTHON_TOOLS=0 bash scripts/bootstrap.sh
```

## AutoDL network turbo

This only sources an AutoDL-provided helper when present. It does not copy or commit the helper.

```bash
source scripts/network-turbo-on.sh
```

## tmux research session

```bash
bash scripts/tmux-research.sh my-exp
```

This opens a shell window, GPU monitor window, and log window. It does not assume a project layout or start training.

## Make shortcuts

```bash
make setup
make doctor
make web-tunnel
make web
make network-first
make check
make proxy-deep-check
make mihomo-start
make mihomo-check
make mihomo-autostart
make mihomo-autostart-status
```
