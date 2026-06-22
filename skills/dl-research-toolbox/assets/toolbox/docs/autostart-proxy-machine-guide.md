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
  Use profile/profile.d/bashrc fallback and describe it precisely.

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

Preferred high-level repair command:

```bash
toolbox repair
```

It refreshes mihomo autostart/profile hooks, starts mihomo, selects a reachable
selector candidate, verifies common proxy egress, checks Codex login egress,
runs official `codex doctor --ascii --summary`, configures the caller Git repo
for local proxy plus `HTTP/1.1`, and inspects Codex app-server proxy env.

Lower-level autostart-only command:

```bash
bash scripts/mihomo-autostart.sh install --mode auto --enable-linger
```

Expected behavior:

- systemd system host: install/enable system service and shell proxy env hook.
- systemd user host: install/enable user service and shell proxy env hook.
- container fallback: refresh profile hook and install shell proxy env hooks.

Root fallback shell env hook path:

```text
/etc/profile.d/99-dl-research-toolbox-proxy.sh
~/.bashrc
```

Managed hook markers:

```text
# >>> dl-research-toolbox mihomo autostart >>>
# <<< dl-research-toolbox mihomo autostart <<<
# >>> dl-research-toolbox shell proxy hook >>>
# <<< dl-research-toolbox shell proxy hook <<<
# >>> dl-research-toolbox bashrc proxy hook >>>
# <<< dl-research-toolbox bashrc proxy hook <<<
```

Install must refresh managed blocks instead of leaving stale paths in place.

## Verify

Run:

```bash
bash -n scripts/mihomo-autostart.sh
bash -n scripts/proxy-on.sh
bash -n scripts/proxy-off.sh
bash -n scripts/network-first-setup.sh
bash -n scripts/network-repair.sh
bash -n scripts/install-toolbox-cli.sh
dash -c '. scripts/proxy-on.sh >/tmp/proxy-on.out; test "$http_proxy" = "http://127.0.0.1:7890"'
dash -c '. scripts/proxy-off.sh >/tmp/proxy-off.out; test -z "${http_proxy:-}"'
bash -lc 'test "$http_proxy" = "http://127.0.0.1:7890"'
bash -ic 'test "$http_proxy" = "http://127.0.0.1:7890"'
toolbox repair status
toolbox check
```

Codex runtime verification:

```bash
codex login status
codex doctor --ascii --summary
printf '%s' 'Reply exactly OK' | codex exec --sandbox read-only --color never --skip-git-repo-check -
```

If `codex doctor` passes in a fresh shell but an existing TUI reports MCP,
`codex_apps`, WebSocket, or request timeouts, inspect already-running Codex
process environments:

```bash
ps -eo pid,ppid,etime,cmd | grep -E '[c]odex|[m]cp'
tr '\0' '\n' </proc/PID/environ | grep -Ei '^(http|https|all|no)_proxy='
```

Restart stale Codex TUI processes that were launched before proxy hooks were
repaired. Restart app-server only through the explicit command because it can
interrupt the current desktop/TUI connection:

```bash
toolbox repair app-server
```

Do not treat account quota or plan-limit responses as proxy-node failures once
`codex doctor` passes.

Smoke-test a clean login shell:

```bash
env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" SHELL=/bin/bash \
  TERM=xterm-256color PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  bash -lc 'env | grep -i proxy | sort; curl -I -L --max-time 20 https://api.openai.com/v1/models | sed -n "1,12p"; command -v codex; codex --version'
```

Pass criteria:

- proxy env vars exist in the clean login shell;
- proxy env vars exist in a fresh interactive bash shell;
- `mihomo` listens on `127.0.0.1:7890`;
- GitHub, Hugging Face, PyPI, npm registry checks pass;
- `codex --version` works;
- `codex doctor --ascii --summary` exits with no failures;
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
  docs/script-usage.md docs/codex-remote-runtime-postmortem.md \
  scripts/network-repair.sh scripts/install-toolbox-cli.sh \
  scripts/mihomo-select-best.sh scripts/codex-login-egress-check.sh \
  scripts/doctor.sh scripts/toolbox-web.py install.sh toolbox
```

Do not stage `mihomo.yaml`.
