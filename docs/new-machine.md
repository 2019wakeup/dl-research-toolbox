# New Machine Setup

This checklist keeps the machine setup generic and project-independent.

## 1. Clone toolbox

```bash
git clone <your-repo-url> dl-research-toolbox
cd dl-research-toolbox
```

## 2. Configure network first

```bash
bash install.sh --mihomo-yaml /path/to/mihomo.yaml
source scripts/proxy-on.sh
```

`install.sh` is the main operator entrypoint. It calls `network-first-setup.sh`, installs mihomo, imports a local Clash/Mihomo YAML file, checks listeners and proxy egress, installs mihomo autostart by default, installs Codex CLI through npm, installs the Linux `bubblewrap` sandbox prerequisite, runs the full bootstrap with proxy variables already active inside the script, then runs `scripts/doctor.sh`. This order prevents later `apt`, `uv`, GitHub, Hugging Face, and Python package downloads from failing due to network issues.

Use a local YAML file for cold-start migration. A subscription URL may be blocked before mihomo is running; `--url` is only for machines that already have direct access to the subscription endpoint.

If an old mihomo process is already using the configured port, rerun with:

```bash
bash install.sh --mihomo-yaml /path/to/mihomo.yaml --replace-running
```

To configure network only and skip the full bootstrap:

```bash
bash install.sh --mihomo-yaml /path/to/mihomo.yaml --no-bootstrap
```

The bootstrap installs common Linux tools plus `gh`, `npm`, `uv`, and a trimmed Python research tools venv at `~/.local/venvs/research-tools`. It does not install conda, PyTorch, CUDA wheels, model code, datasets, or checkpoints.

To skip the Python tools venv when bootstrap runs:

```bash
bash install.sh --mihomo-yaml /path/to/mihomo.yaml --skip-python-tools
```

## 3. Configure mihomo manually when needed

```bash
bash scripts/mihomo-install.sh
bash scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml
source scripts/proxy-on.sh
```

The import script reads a local Clash/Mihomo YAML file by default, writes the generated config to `~/.config/mihomo/config.yaml`, validates it with `mihomo -t`, starts mihomo, then checks listeners and proxy egress. Keep the real config outside this repository.

If an old mihomo process is already using the configured port, rerun with:

```bash
bash scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml --replace-running
```

Raw node-list subscriptions such as `ss://`, `vmess://`, `vless://`, or `trojan://` are not imported directly. Convert them locally to Clash/Mihomo YAML first, then import with `--file`.

## 4. Start proxy

```bash
bash scripts/mihomo-start.sh
source scripts/proxy-on.sh
```

For one-off AutoDL acceleration, use:

```bash
source scripts/network-turbo-on.sh
```

## 5. Validate

```bash
bash scripts/doctor.sh
```

## 6. mihomo autostart

`network-first-setup.sh` installs mihomo autostart by default after a successful YAML import. For manual setup or repair, run:

```bash
# Auto mode uses system service when possible and falls back to user/profile modes.
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
bash scripts/mihomo-autostart.sh status

# True boot autostart on normal systemd machines.
bash scripts/mihomo-autostart.sh install --mode system
```

Use `--no-autostart` with `network-first-setup.sh` only when the machine should not persist proxy startup. Use `--mode profile` only when systemd services are unavailable. Profile mode starts mihomo when a shell profile is read, not necessarily before login.

## 7. Optional Web UI over SSH forwarding

For the smoothest workflow, keep a local copy of the toolbox repository and run:

```bash
bash scripts/web-tunnel.sh
```

On the first run, the helper asks for the SSH target, SSH port, and remote repository directory, then saves them locally. Later runs are the same one command.

For non-interactive setup, save the profile explicitly:

```bash
bash scripts/web-tunnel.sh --target user@server --ssh-port 22 --remote-dir '~/dl-research-toolbox' --save-profile
```

This opens the SSH tunnel and starts the remote Web UI in one command.

Manual fallback on the server:

```bash
cd ~/dl-research-toolbox
bash scripts/web-ui.sh --port 8765
```

Manual tunnel from the local machine:

```bash
ssh -N -L 8765:127.0.0.1:8765 user@server
```

Open the tokenized local URL printed by the server command.

## 8. Script usage guide

See [script-usage.md](script-usage.md) for post-install commands, validation, autostart, proxy toggles, and tmux helper usage.

## 9. Remote experiment session

```bash
bash scripts/tmux-research.sh my-exp
```

The helper opens a shell window, a GPU monitor window, and a log window. It does not start training jobs or assume a project layout.
