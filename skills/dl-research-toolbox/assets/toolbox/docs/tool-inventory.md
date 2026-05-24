# Source Machine Tool Inventory

This inventory was used to shape the generic toolbox. It is descriptive only; the repository does not copy project files, binaries, datasets, checkpoints, or sensitive config from the source machine.

## Detected generic tools

- Git: `/usr/bin/git`
- tmux: `/usr/bin/tmux`
- curl: `/usr/bin/curl`
- wget: `/usr/bin/wget`
- aria2c: `/usr/bin/aria2c`
- jq: `/usr/bin/jq`
- ripgrep: `/usr/bin/rg`
- htop: `/usr/bin/htop`
- rsync: `/usr/bin/rsync`
- nvidia-smi: `/usr/bin/nvidia-smi`
- nvcc: `/usr/local/cuda/bin/nvcc`
- nvitop: present under an existing Python environment
- gdown: present under an existing Python environment

## Detected network setup

- AutoDL acceleration entrypoint exists at `/etc/network_turbo`.
- A local mihomo setup exists under `/root/autodl-tmp/projects/mihomo-for-autodl`.
- The running mihomo shape is a user process with `mihomo -d <config-dir>`.

The toolbox keeps only this reusable shape:

- conditional sourcing of `/etc/network_turbo` when present;
- user-local mihomo installation under `~/.local/opt/mihomo`;
- config under `~/.config/mihomo`;
- state/logs under `~/.local/state/mihomo`;
- proxy variables pointing to `127.0.0.1:7890`.

## Explicitly not imported

- `/root/autodl-tmp/baseline-RLDD`
- `/root/autodl-tmp/feature-extraction`
- `/root/autodl-tmp/projects/*`
- `/root/autodl-tmp/datasets`
- `/root/autodl-tmp/models`
- `/root/autodl-tmp/checkpoints`
- `/root/autodl-tmp/miniconda3`
- real mihomo `config.yaml`, subscriptions, nodes, controller secrets, caches, logs, and rule databases

## Tools intentionally left optional

- `gh`
- `uv`
- `yq`
- `rclone`
- `huggingface-cli`
- conda/mamba/micromamba
- PyTorch and project Python dependencies

These may be useful on some machines, but they are intentionally not part of the generic baseline because they either require account-specific authentication, project-specific choices, or a concrete Python environment strategy.
