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
mkdir -p ~/.config/mihomo
cp network/mihomo/config.yaml.example ~/.config/mihomo/config.yaml
$EDITOR ~/.config/mihomo/config.yaml
```

Paste your own proxy nodes or provider configuration into `~/.config/mihomo/config.yaml`. Keep the real config outside this repository.

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
bash scripts/mihomo-status.sh
```

## 6. Remote experiment session

```bash
bash scripts/tmux-research.sh my-exp
```

The helper opens a shell window, a GPU monitor window, and a log window. It does not start training jobs or assume a project layout.
