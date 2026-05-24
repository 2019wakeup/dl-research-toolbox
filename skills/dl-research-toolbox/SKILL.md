---
name: dl-research-toolbox
description: Build, install, update, or maintain a project-independent deep learning research machine toolbox. Use when setting up a new Linux/GPU research machine; packaging reusable DL research environment tooling; installing generic CLI tools such as gh, npm, uv, tmux, rg, jq, and git-lfs; configuring mihomo/Clash subscription import and proxy checks; or auditing that the toolbox excludes project code, datasets, checkpoints, conda, PyTorch, CUDA wheels, secrets, and real proxy credentials.
---

# DL Research Toolbox

Use this skill to produce or operate the lightweight toolbox that prepares a generic research machine without binding it to a specific project or training framework.

## Core Rules

- Keep the toolbox project-independent: no datasets, checkpoints, model weights, experiment logs, project code, or paper-specific scripts.
- Do not install or pin conda, PyTorch, TensorFlow, CUDA wheels, or project dependencies.
- Never commit real mihomo `config.yaml`, subscription URLs, proxy nodes, tokens, cookies, SSH keys, or API credentials.
- Prefer user-local paths: `~/.local/bin`, `~/.local/opt`, `~/.local/venvs/research-tools`, `~/.config/mihomo`, `~/.local/state/mihomo`.
- Validate with dry-runs and syntax checks before running network or package installation steps.

## Quick Install

To materialize the bundled toolbox into a target directory:

```bash
bash <skill-dir>/scripts/install_toolbox.sh --path ~/dl-research-toolbox
```

To install and bootstrap in one pass:

```bash
bash <skill-dir>/scripts/install_toolbox.sh --path ~/dl-research-toolbox --bootstrap --install-mihomo
```

To fetch the latest GitHub version instead of using the bundled asset:

```bash
bash <skill-dir>/scripts/install_toolbox.sh --from-git --path ~/dl-research-toolbox
```

## Workflow

1. Inspect the target machine and workspace. Check existing repos, dirty worktrees, and whether `~/.config/mihomo/config.yaml` already exists.
2. Install or update the toolbox using `scripts/install_toolbox.sh`. Use the bundled asset when GitHub credentials are unavailable; use `--from-git` when the remote repository should be the source of truth.
3. Run `bash scripts/bootstrap.sh --dry-run` from the materialized toolbox. Confirm it installs only generic tools plus the trimmed Python tools venv.
4. Run `bash scripts/bootstrap.sh` only when the user wants packages installed.
5. Configure networking with `bash scripts/mihomo-install.sh`, then `bash scripts/mihomo-import-subscription.sh` for interactive subscription import. Use `--replace-running` only when replacing an old mihomo process is intended.
6. Validate with `bash scripts/check-machine.sh` and `bash scripts/mihomo-status.sh --strict --test-proxy`.
7. If editing the toolbox itself, run `bash -n scripts/*.sh` for changed shell scripts, `git diff --check`, sensitive keyword grep, then commit and push.

## Bundled Resources

- `scripts/install_toolbox.sh`: materializes this skill's bundled toolbox asset or clones/updates the GitHub repo.
- `assets/toolbox/`: self-contained copy of the lightweight toolbox template.
- `references/toolbox-scope.md`: package scope, included tools, and exclusions.
- `references/networking.md`: mihomo import, listener checks, and proxy validation notes.

Read the relevant reference only when the task needs those details.
