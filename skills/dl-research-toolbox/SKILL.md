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

To install with the recommended network-first order:

```bash
bash <skill-dir>/scripts/install_toolbox.sh --path ~/dl-research-toolbox --network-first --mihomo-file /path/to/mihomo.yaml
```

To fetch the latest GitHub version instead of using the bundled asset:

```bash
bash <skill-dir>/scripts/install_toolbox.sh --from-git --path ~/dl-research-toolbox
```

## Workflow

1. Inspect the target machine and workspace. Check existing repos, dirty worktrees, and whether `~/.config/mihomo/config.yaml` already exists.
2. Install or update the toolbox using `scripts/install_toolbox.sh`. Use the bundled asset when GitHub credentials are unavailable; use `--from-git` when the remote repository should be the source of truth.
3. Prefer the top-level entrypoint with a local YAML file: `bash install.sh --mihomo-yaml /path/to/mihomo.yaml`. It installs/configures mihomo first, imports local Clash/Mihomo YAML, installs mihomo autostart by default, enables proxy variables for the script process, installs Codex CLI, runs full bootstrap through the proxy, then runs `scripts/doctor.sh`. Use `--url` only when direct access to the subscription endpoint already works.
4. Use `bash install.sh --mihomo-yaml /path/to/mihomo.yaml --no-bootstrap` when the user wants only proxy setup first.
5. Use `bash scripts/bootstrap.sh --dry-run` only for inspection, or after proxy is known working.
6. Validate with `bash scripts/doctor.sh`; use `bash scripts/doctor.sh --quick` for proxy-only validation.
7. Treat persistent proxy startup as the default after network-first setup. For manual repair, use `bash scripts/mihomo-autostart.sh install --mode auto --enable-linger`; use explicit `--mode system`, `--mode user --enable-linger`, or `--mode profile` only when appropriate.
8. For SSH-forwarded monitoring/control, use `bash scripts/web-ui.sh --port 8765` and forward with `ssh -N -L 8765:127.0.0.1:8765 user@server`.
9. For script usage after installation, read `docs/script-usage.md`.
10. If editing the toolbox itself, run `bash -n scripts/*.sh` for changed shell scripts, `git diff --check`, sensitive keyword grep, then commit and push.

## Bundled Resources

- `scripts/install_toolbox.sh`: materializes this skill's bundled toolbox asset or clones/updates the GitHub repo; use `--network-first --mihomo-file PATH` for direct setup, or run the generated toolbox's `install.sh`.
- `assets/toolbox/`: self-contained copy of the lightweight toolbox template.
- `references/toolbox-scope.md`: package scope, included tools, and exclusions.
- `references/networking.md`: mihomo import, autostart, listener checks, and proxy validation notes.
- `references/migration-engineering-notes.md`: migration failure modes and fixes to remember.

Read the relevant reference only when the task needs those details.
