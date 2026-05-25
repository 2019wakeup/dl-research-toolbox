# Script Usage Guide

This guide covers the scripts you normally use after installing the toolbox on a new machine. Commands assume you are in the toolbox directory.

## Network-first setup

Use this on a fresh machine. It installs mihomo first, imports your local YAML or subscription, enables proxy variables for the script process, installs Codex CLI, then runs full bootstrap through the proxy.

```bash
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml
```

Common variants:

```bash
# Replace an old mihomo process already holding the port.
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml --replace-running

# Configure proxy and Codex CLI only; skip full bootstrap.
bash scripts/network-first-setup.sh --file /path/to/mihomo.yaml --no-bootstrap

# Use a subscription URL instead of a local YAML file.
bash scripts/network-first-setup.sh --url 'https://example.com/sub.yaml'
```

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

Import a local Clash/Mihomo YAML file:

```bash
bash scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml --replace-running
```

Interactive URL import is also supported; the URL is not echoed:

```bash
bash scripts/mihomo-import-subscription.sh
```

The real generated config lives in `~/.config/mihomo/config.yaml`. Do not copy that file into this repository.

## Autostart

Immediate start is handled by `mihomo-start.sh`. Persistent startup is handled by `mihomo-autostart.sh`.

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

Basic machine check:

```bash
bash scripts/check-machine.sh
```

Proxy process, listeners, controller, and proxy egress:

```bash
bash scripts/mihomo-status.sh --strict --test-proxy
```

Deep proxy validation across common research download paths:

```bash
bash scripts/verify-proxy-deep.sh
```

The deep check covers proxy environment variables, mihomo strict status, curl to GitHub/Hugging Face/PyPI/npm registry, Git over HTTPS, `npm view`, Codex CLI, `uv`, and selected Python research-tool imports.

## Codex CLI

Install or repair Codex CLI after proxy is available:

```bash
bash scripts/install-codex-cli.sh
codex --version
```

The script ensures a modern Node.js is installed, handles Ubuntu Node 12 conflicts, reinstalls broken Codex CLI packages, and persists `~/.local/bin` into shell profiles.

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
make network-first
make check
make proxy-deep-check
make mihomo-start
make mihomo-check
make mihomo-autostart
make mihomo-autostart-status
```
