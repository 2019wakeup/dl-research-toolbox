# Migration Engineering Notes

This document records reusable engineering lessons from migrating the toolbox to a fresh GPU Linux machine. It excludes real proxy nodes, subscription URLs, passwords, tokens, datasets, checkpoints, and project-specific dependencies.

## Network and proxy

- Configure mihomo before full bootstrap. Later package operations should inherit `http_proxy`, `https_proxy`, and `all_proxy` from `scripts/proxy-on.sh`.
- Treat HTTP/HTTPS proxy egress as the critical path for research setup. A DNS UDP listener can be useful, but it should not block setup when `mixed-port`, controller, and proxy egress pass.
- `mihomo-status.sh --strict --test-proxy` should work even before `ss` or `lsof` are installed. When listener enumeration tools are missing, use controller and curl proxy probes as the meaningful checks.
- Use `scripts/verify-proxy-deep.sh` after setup to check GitHub, raw GitHub content, Hugging Face API, PyPI, npm registry, Git over HTTPS, Codex CLI, uv, and Python research-tool imports.

## Codex CLI and Node.js

- Ubuntu 22.04 repository `npm` can install Node 12, which is too old for current `@openai/codex`. The Codex installer must ensure Node.js >= 16, currently by installing NodeSource Node 22 when needed.
- Switching from Ubuntu Node 12 to NodeSource Node can conflict with `nodejs`, `npm`, `libnode-dev`, and `libnode72`. The installer should repair dpkg state and remove Debian Node packages before installing NodeSource `nodejs`.
- A Codex CLI installed under the wrong Node version can miss optional platform packages such as `@openai/codex-linux-x64`. If `codex --version` fails, reinstall `@openai/codex@latest`.
- Persist `~/.local/bin` in both `.bashrc` and `.profile`, because non-interactive SSH, login shells, and fresh terminals do not always read the same startup file.

## Bootstrap idempotency

- Bootstrap can be interrupted after creating `~/.local/venvs/research-tools`. Re-running must reuse a complete venv or clear and rebuild a partial one.
- Scripts should prefer user-local paths and be safe to rerun. Generated real mihomo config belongs in `~/.config/mihomo`, not in this repository.
- Temporary YAML import files should be deleted after import on remote machines.

## Autostart

- `scripts/mihomo-start.sh` is the immediate start command.
- `scripts/mihomo-autostart.sh install --mode system` is true boot autostart on normal systemd machines.
- `scripts/mihomo-autostart.sh install --mode user --enable-linger` is appropriate when a systemd user manager is available.
- `scripts/mihomo-autostart.sh install --mode profile` is a fallback for containers or SSH environments without systemd; it starts mihomo when the shell profile is read, not necessarily at machine boot.
