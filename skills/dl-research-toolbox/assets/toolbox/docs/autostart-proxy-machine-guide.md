# Autostart Proxy Machine Guide

Audience: automation agents, Codex sessions, and maintenance scripts.

Purpose: configure `dl-research-toolbox` proxy startup without leaking real
Mihomo configuration or assuming a service manager exists.

## Invariants

- Do not commit real proxy material:
  - `mihomo.yaml`
  - `~/.config/mihomo/config.yaml`
  - node definitions, provider URLs, subscription URLs, tokens, cookies, keys
- Do not edit generated real Mihomo config unless the user explicitly asks.
- Do not stage untracked real config files.
- Treat HTTP 2xx, 3xx, and 4xx from public endpoints as transport success.
- Treat `https://api.openai.com/v1/models` returning `HTTP/2 401` without
  credentials as a successful network reachability check.
- On containers without systemd, do not claim true pre-shell boot autostart.
  Use profile/profile.d fallback and describe it precisely.

## Detection

Run from the repo root:

```bash
pwd
git status --short
git branch --show-current
git remote -v
ps -p 1 -o comm= 2>/dev/null || cat /proc/1/comm 2>/dev/null || true
command -v systemctl || true
systemctl --user show-environment >/dev/null 2>&1; echo "user_systemd=$?"
ls -l "$HOME/.local/bin/mihomo" "$HOME/.config/mihomo/config.yaml" 2>/dev/null || true
```

Classify the host:

```text
systemd system available: command -v systemctl && [ -d /run/systemd/system ]
systemd user available:   systemctl --user show-environment succeeds
container fallback:       neither system nor user systemd is available
```

## Install or Repair

Preferred command:

```bash
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
```

Expected behavior:

- systemd system host: install/enable system service and shell proxy env hook.
- systemd user host: install/enable user service and shell proxy env hook.
- container fallback: refresh profile hook and install shell proxy env hook.

Root fallback shell env hook path:

```text
/etc/profile.d/99-dl-research-toolbox-proxy.sh
```

Managed hook markers:

```text
# >>> dl-research-toolbox mihomo autostart >>>
# <<< dl-research-toolbox mihomo autostart <<<
# >>> dl-research-toolbox shell proxy hook >>>
# <<< dl-research-toolbox shell proxy hook <<<
```

Install must refresh managed blocks instead of leaving stale paths in place.

## Verify

Run:

```bash
bash -n scripts/mihomo-autostart.sh
bash -n scripts/proxy-on.sh
bash -n scripts/proxy-off.sh
bash -n scripts/network-first-setup.sh
dash -c '. scripts/proxy-on.sh >/tmp/proxy-on.out; test "$http_proxy" = "http://127.0.0.1:7890"'
dash -c '. scripts/proxy-off.sh >/tmp/proxy-off.out; test -z "${http_proxy:-}"'
bash scripts/mihomo-autostart.sh status
bash scripts/verify-proxy-deep.sh
```

Smoke-test a clean login shell:

```bash
env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" SHELL=/bin/bash \
  TERM=xterm-256color PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  bash -lc 'env | grep -i proxy | sort; curl -I -L --max-time 20 https://api.openai.com/v1/models | sed -n "1,12p"; command -v codex; codex --version'
```

Pass criteria:

- proxy env vars exist in the clean login shell;
- `mihomo` listens on `127.0.0.1:7890`;
- GitHub, Hugging Face, PyPI, npm registry checks pass;
- `codex --version` works;
- no stale `/root/dl-research-toolbox` hook remains when the active repo is
  elsewhere.

## Git Hygiene

Before commit:

```bash
git status --short
git diff --stat
git diff --check
git grep -nE 'subscription|token|secret|password|passwd|cookie|Authorization|Bearer|proxy-provider|proxies:' -- .
```

Stage only tracked source/docs plus intended new docs. Example:

```bash
git add README.md docs/autostart-proxy-guide.md docs/autostart-proxy-machine-guide.md \
  docs/script-usage.md docs/migration-engineering-notes.md \
  scripts/mihomo-autostart.sh scripts/network-first-setup.sh \
  scripts/proxy-on.sh scripts/proxy-off.sh
```

Do not stage `mihomo.yaml`.
