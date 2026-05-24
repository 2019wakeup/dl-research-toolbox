# New Machine Setup

This checklist keeps the machine setup generic and project-independent.

## 1. Clone toolbox

```bash
git clone <your-repo-url> dl-research-toolbox
cd dl-research-toolbox
```

## 2. Install base CLI

```bash
bash scripts/bootstrap.sh --dry-run
bash scripts/bootstrap.sh
```

The bootstrap installs common Linux tools only. It does not install conda, PyTorch, CUDA wheels, model code, datasets, or checkpoints.

## 3. Configure mihomo

```bash
bash scripts/mihomo-install.sh
bash scripts/mihomo-import-subscription.sh
source scripts/proxy-on.sh
```

The import script prompts for a Clash/Mihomo subscription URL without echo, writes the generated config to `~/.config/mihomo/config.yaml`, validates it with `mihomo -t`, starts mihomo, then checks listeners and proxy egress. Keep the real config outside this repository.

If an old mihomo process is already using the configured port, rerun with:

```bash
bash scripts/mihomo-import-subscription.sh --replace-running
```

Raw node-list subscriptions such as `ss://`, `vmess://`, `vless://`, or `trojan://` are not imported directly. Use a Clash/Mihomo subscription URL or convert locally first.

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
bash scripts/check-machine.sh
bash scripts/mihomo-status.sh --strict --test-proxy
```

## 6. Remote experiment session

```bash
bash scripts/tmux-research.sh my-exp
```

The helper opens a shell window, a GPU monitor window, and a log window. It does not start training jobs or assume a project layout.
