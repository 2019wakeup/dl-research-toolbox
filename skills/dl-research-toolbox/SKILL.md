---
name: dl-research-toolbox
description: Build, install, update, or maintain a project-independent deep learning research machine toolbox. Use when setting up a new Linux/GPU research machine; packaging reusable DL research environment tooling; installing generic CLI tools such as gh, npm, uv, tmux, rg, jq, and git-lfs; configuring mihomo/Clash subscription import, proxy checks, Codex CLI device-code login egress checks, and Codex runtime diagnostics; or auditing that the toolbox excludes project code, datasets, checkpoints, conda, PyTorch, CUDA wheels, secrets, and real proxy credentials.
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
3. Prefer the installed CLI entrypoint after setup: `toolbox <command>`. From a fresh clone before PATH setup, run `./toolbox install-cli` first or use `./toolbox` as a temporary fallback. The CLI installer maintains `~/.local/bin/toolbox` and, when root or a writable system bin directory is available, `/usr/local/bin/toolbox` for non-interactive SSH. For a local YAML install, use `toolbox setup --mihomo-yaml /path/to/mihomo.yaml` or `bash install.sh --mihomo-yaml /path/to/mihomo.yaml`. It installs/configures mihomo first, imports local Clash/Mihomo YAML, installs mihomo autostart by default, enables proxy variables for the script process, installs Codex CLI plus the Linux `bubblewrap` sandbox prerequisite, runs full bootstrap through the proxy, then runs `scripts/doctor.sh`. Use `--url` only when direct access to the subscription endpoint already works.
4. Use `bash install.sh --mihomo-yaml /path/to/mihomo.yaml --no-bootstrap` when the user wants only proxy setup first.
5. Use `bash scripts/bootstrap.sh --dry-run` only for inspection, or after proxy is known working.
6. Validate with `toolbox check` or `bash scripts/doctor.sh --quick`; use `toolbox doctor` or `bash scripts/doctor.sh` for full checks. If controller/listeners are healthy but normal egress fails, run `toolbox repair` first. It refreshes autostart hooks, starts mihomo, short-scans selectors, verifies proxy egress, checks Codex login egress, runs official `codex doctor --ascii --summary`, configures Git proxy/HTTP/1.1, and inspects app-server proxy env. Use `toolbox repair --deep` for a broader selector scan. If Codex login reports `403 Forbidden` or cannot request a device code, run `toolbox codex-ready` or `bash scripts/codex-login-egress-check.sh repair` to find a selector that can reach the Codex login endpoint.
7. Treat persistent proxy startup as the default after network-first setup. For manual repair, use `bash scripts/mihomo-autostart.sh install --mode auto --enable-linger`; on containers this must refresh profile/profile.d/bashrc hooks so both login shells and interactive bash inherit proxy variables.
8. For SSH-forwarded monitoring/control, prefer local-side `bash scripts/web-tunnel.sh`; its first run asks for the SSH target and saves a local profile. Use `bash scripts/web-tunnel.sh --target user@server --ssh-port PORT --remote-dir '~/dl-research-toolbox' --save-profile` for non-interactive setup, and remote-side `bash scripts/web-ui.sh --port 8765` only as the manual fallback.
9. When the repository is used as a Codex skill bundle, run `bash scripts/install-codex-skills.sh` from the repo to sync bundled skills into `${CODEX_HOME:-$HOME/.codex}/skills`.
10. For research project repositories, install the executable guard with `bash skills/research-version-isolation/scripts/install_research_hooks.sh /path/to/research-repo` to enforce single-root memory, upward task sync, and classified experiment logs.
11. For script usage after installation, read `docs/script-usage.md`.
12. For remote/headless Codex auth, prefer `codex login --device-auth`, then run `codex doctor --ascii --summary`. If Codex is logged in but doctor reports WebSocket or provider reachability failures, run `toolbox repair codex`. If a fresh shell passes but an existing TUI reports MCP, `codex_apps`, WebSocket, or request timeouts, inspect running Codex process environments and use `toolbox repair app-server` only when the explicit app-server restart is acceptable.
13. If Codex reports missing bubblewrap, run `bash scripts/install-codex-cli.sh` or `bash scripts/check-codex-sandbox.sh`; distinguish missing `bwrap` on PATH from host/container namespace denial.
14. If editing the toolbox itself, run `bash -n` for changed shell scripts, `toolbox repair status --no-strict` when network behavior changed, `git diff --check`, sensitive keyword grep, then commit and push.

## Bundled Resources

- Top-level `scripts/install-codex-skills.sh`: installs or updates all Codex skills bundled in the repository.
- `scripts/install_toolbox.sh`: materializes this skill's bundled toolbox asset or clones/updates the GitHub repo; use `--network-first --mihomo-file PATH` for direct setup, or run the generated toolbox's `install.sh`.
- `assets/toolbox/`: self-contained copy of the lightweight toolbox template.
- `references/toolbox-scope.md`: package scope, included tools, and exclusions.
- `references/networking.md`: mihomo import, autostart, listener checks, proxy validation, Codex login egress, and runtime diagnostics notes.
- `references/migration-engineering-notes.md`: migration failure modes and fixes to remember.
- Repository sibling skills: `dataset-download-network`, `remote-project-memory`, `research-version-isolation`, and `deep-learning-research` provide dataset download diagnostics, project memory, version isolation, experiment contracts, and hook enforcement for actual research repositories.

Read the relevant reference only when the task needs those details.
