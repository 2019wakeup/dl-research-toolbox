# Script Usage Guide

This guide covers the scripts you normally use after installing the toolbox on a new machine. Day-to-day commands use the installed `toolbox` CLI. The CLI installer maintains `~/.local/bin/toolbox` and, when running as root or with a writable system bin directory, `/usr/local/bin/toolbox` for non-interactive SSH. When working from a fresh clone before PATH setup, run `./toolbox install-cli` first or use `./toolbox` as a temporary fallback.

## Unified entrypoint

Prefer the installed `toolbox` command for day-to-day use. It keeps the common tasks discoverable while preserving the lower-level scripts for debugging and automation.

```bash
toolbox help
toolbox install-cli
toolbox setup --mihomo-yaml /path/to/mihomo.yaml
toolbox status
toolbox doctor
toolbox check
toolbox repair
toolbox repair status
toolbox repair codex
toolbox codex-ready
toolbox mihomo restart
toolbox autostart
```

## One-command setup

Use the unified wrapper on a fresh machine. It detects `./mihomo.yaml` or `~/mihomo.yaml` automatically, or accepts an explicit path. It runs network-first setup and then `scripts/doctor.sh`.

```bash
toolbox setup --mihomo-yaml /path/to/mihomo.yaml
```

Common variants:

```bash
toolbox proxy-only --mihomo-yaml /path/to/mihomo.yaml
toolbox setup --mihomo-yaml /path/to/mihomo.yaml --replace-running
toolbox setup --mihomo-yaml /path/to/mihomo.yaml --skip-python-tools
toolbox setup --mihomo-yaml /path/to/mihomo.yaml --dry-run
```

## Fast network repair

Use this when Codex, GitHub, Hugging Face, PyPI, npm, or Git suddenly stops working after the machine was previously healthy:

```bash
toolbox repair
```

The default repair refreshes mihomo autostart and shell hooks, starts mihomo, runs a short selector scan, verifies common proxy egress, checks Codex login egress, runs official `codex doctor --ascii --summary`, configures the current Git repository for the local proxy and `HTTP/1.1`, and checks whether Codex app-server inherited proxy variables.

Common targeted repairs:

```bash
toolbox repair status
toolbox repair proxy
toolbox repair codex
toolbox repair git --repo /path/to/repo
toolbox repair app-server
toolbox repair --deep
```

Use `toolbox repair app-server` only when Codex still reports app-server, MCP, WebSocket, or request timeouts after `toolbox repair codex` passes. It restarts `codex app-server` processes and can interrupt the current Codex desktop/TUI connection.

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

## Codex login egress

Codex ChatGPT login uses `chatgpt.com/backend-api/codex/deviceauth/usercode`, not only `api.openai.com`. A proxy node can pass OpenAI API checks while still returning `403 Forbidden` for the device-code login endpoint. `doctor.sh` and `toolbox check` include this egress check by default. Before logging in, or after changing/restarting mihomo, run:

```bash
toolbox codex-ready
```

This command first checks the current selector. If the current node cannot request a Codex device code, it scans mihomo selector candidates and switches to one that can. Output uses candidate indexes instead of real node names, and any generated one-time device code is captured and redacted.

If Codex is already logged in, the check does not run `codex login --device-auth` by default, because the device-code login flow can disturb the active cached session. Use `--force-device-probe` only when you explicitly want to test the login flow itself.

To check without changing selectors:

```bash
toolbox codex-login check
```

Force the device-code probe even when already logged in:

```bash
toolbox codex-login check --force-device-probe
```

To repair with a smaller scan window:

```bash
toolbox codex-login repair --scan-limit 40
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

Autostart installation also refreshes shell proxy environment hooks by default. On root-owned machines this writes `/etc/profile.d/99-dl-research-toolbox-proxy.sh` and refreshes `~/.bashrc`, so new login shells and interactive bash shells start mihomo if needed and export `http_proxy`, `https_proxy`, and `all_proxy` automatically. Use `--no-shell-env` only if you want mihomo to run without changing shell proxy variables.

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

In containers where PID 1 is not systemd, profile mode is the available fallback: it cannot run before any shell exists, but it makes SSH/login and interactive bash shells seamless by starting mihomo and enabling proxy variables automatically.

Remove all autostart entries:

```bash
bash scripts/mihomo-autostart.sh uninstall
```

## Validation

Unified post-install check. It sources `scripts/proxy-on.sh` by default:

```bash
bash scripts/doctor.sh
```

Quick base check:

```bash
bash scripts/doctor.sh --quick
```

The quick doctor runs `check-machine.sh`, `mihomo-status.sh --strict --test-proxy`, `codex doctor --ascii --summary`, and `codex-login-egress-check.sh check`. The full doctor runs those same base checks, then adds `verify-proxy-deep.sh --no-codex-login`. The deep check covers proxy environment variables, curl to GitHub/Hugging Face/PyPI/npm registry, Git over HTTPS, `npm view`, Codex CLI, `uv`, and selected Python research-tool imports.

## Codex CLI

Install or repair Codex CLI after proxy is available:

```bash
bash scripts/install-codex-cli.sh
codex --version
```

For headless or remote servers, prefer the official device-code login path:

```bash
codex login --device-auth
```

After login, use the official local diagnostic before starting long work:

```bash
codex doctor --ascii --summary
```

If `codex doctor` reports missing proxy environment, WebSocket timeout, or unreachable provider endpoints, run the Codex-focused repair first:

```bash
toolbox repair codex
```

For a shell-only manual fallback, open a new shell or run:

```bash
source scripts/proxy-on.sh
```

If an existing Codex TUI was started before proxy hooks were fixed, exit it and start a fresh `codex` process so it inherits the repaired environment. If app-server or MCP errors continue after `toolbox repair codex` passes, run:

```bash
toolbox repair app-server
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

## Codex skills

Install or update the Codex skills bundled in this repository:

```bash
bash scripts/install-codex-skills.sh
```

List bundled skills or install only one:

```bash
bash scripts/install-codex-skills.sh --list
bash scripts/install-codex-skills.sh --skill dataset-download-network
bash scripts/install-codex-skills.sh --skill research-version-isolation
```

For a research project repository, install the executable memory/version guard:

```bash
bash skills/research-version-isolation/scripts/install_research_hooks.sh /path/to/research-repo
```

Use `dataset-download-network` when a project needs reliable Hugging Face, ModelScope, OpenXLab, Kaggle, Git LFS, DVC/DataLad, rclone, or HTTP mirror downloads. The research guard enforces a single root memory source, upward task sync for child/domain changes, and classified experiment logs under `research/experiments/<phase>/<series>/<run_id>/`.

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
make repair
make repair-status
make repair-codex
make web-tunnel
make web
make network-first
make check
make proxy-deep-check
make install-skills
make skills-list
make mihomo-start
make mihomo-check
make mihomo-autostart
make mihomo-autostart-status
```
