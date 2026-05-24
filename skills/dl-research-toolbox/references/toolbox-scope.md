# Toolbox Scope

## Included by bootstrap

System/CLI tools:

- `gh`, `git`, `git-lfs`, `npm`, `uv`
- `tmux`, `curl`, `wget`, `aria2`, `jq`, `rg`, `fzf`, `htop`, `rsync`, `lsof`, `ssh`
- build basics such as `build-essential`, `cmake`, `pkg-config`, archive tools

Trimmed Python tools venv at `~/.local/venvs/research-tools`:

- Data/science basics: `numpy`, `pandas`, `scipy`, `scikit-learn`
- Plotting and IO: `matplotlib`, `pillow`, `opencv-python-headless`, `h5py`
- Workflow/config: `tqdm`, `rich`, `pyyaml`, `einops`
- Research utilities: `tensorboard`, `huggingface-hub`, `datasets`, `gdown`, `nvitop`
- Quality/dev: `pytest`, `ruff`, `ipykernel`

## Excluded by design

- conda/mamba/micromamba environments
- PyTorch, TensorFlow, CUDA wheels, driver installers
- project source code, project requirements, experiment configs
- datasets, model weights, checkpoints, logs, `wandb/`, `mlruns/`, artifacts
- real proxy subscriptions, mihomo nodes, secrets, tokens, SSH keys

## Validation commands

```bash
bash scripts/bootstrap.sh --dry-run
bash -n scripts/bootstrap.sh scripts/check-machine.sh scripts/mihomo-import-subscription.sh scripts/mihomo-status.sh
git diff --check
git grep -nE 'token|secret|password|passwd|cookie|Authorization|Bearer|subscription|proxy-provider' -- .
```

Keyword grep may match documentation and empty templates. Investigate matches before pushing.
