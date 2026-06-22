# Codex Remote Runtime Postmortem

Date: 2026-06-18

This note records a real failure mode seen on an AutoDL/SeetaCloud Linux machine.
The machine could install Codex and eventually log in, but interactive Codex still
looked unusable. The final state was not one bug; it was a stack of separate
failure layers.

Update on 2026-06-22: the same machine later showed a different failure mode.
Codex was already logged in, and app-server processes did inherit proxy
environment variables, but the active mihomo selector pointed at an unreachable
outbound node. `codex doctor --ascii --summary` reported WebSocket and provider
reachability failures. `toolbox mihomo check` showed TLS EOF failures, and the
mihomo log showed outbound TCP timeout to the selected node. Running a short
selector scan restored proxy egress and made `codex doctor` pass again.

## What Happened

The first visible failure happened during interactive login:

```text
account/login/start failed: failed to request device code: device code request failed with status 403 Forbidden
```

Direct device-code login worked:

```bash
codex login --device-auth
```

After login, the TUI still failed. It showed an MCP startup timeout for
`codex_apps`, then normal prompts timed out. The official Codex diagnostic was
the turning point:

```bash
codex doctor --ascii --summary
```

When run from a shell without proxy variables, Codex reported unreachable
provider endpoints and WebSocket failures. When run from a login shell that had
`http_proxy`, `https_proxy`, and `all_proxy`, the same diagnostic passed.

## Root Causes

1. `api.openai.com` reachability was not enough.
   Codex ChatGPT login also calls `chatgpt.com/backend-api/codex/deviceauth/usercode`.
   A node can pass normal API checks while failing the Codex device-code endpoint.

2. The interactive `codex login` menu and direct `codex login --device-auth`
   did not behave the same in this environment. The direct headless command was
   the reliable official path for the remote machine.

3. The first version of the toolbox's device-code egress probe reused
   `codex login --device-auth` even when Codex was already logged in. That was
   unsafe because the login flow can disturb the active cached session.

4. The proxy hook covered login shells but missed plain interactive bash in some
   SSH/AutoDL paths. `mihomo` was running, but Codex could still start without
   proxy environment variables.

5. A long-lived Codex app-server process had been started before the proxy
   environment was fixed. Its environment did not include proxy variables, so
   `chatgpt.com/backend-api/ps/mcp` failed even after new shells were repaired.

6. After network and auth were repaired, a separate account quota window became
   the active blocker. That state is not machine-side network failure.

7. A healthy autostart setup can still fail later if the active selector node
   goes bad. In that state, `mihomo` is listening and proxy env exists, but
   common HTTPS egress and Codex provider reachability fail until selector
   groups are switched to a reachable node.

## Fixes Applied

- Added `scripts/codex-login-egress-check.sh` and `toolbox codex-ready` to
  test and repair the Codex device-code login egress.
- Updated the login egress check so it skips `codex login --device-auth` when
  Codex is already logged in. Use `--force-device-probe` only for explicit
  login-flow testing.
- Added the Codex login egress check to default toolbox diagnostics.
- Extended `scripts/mihomo-autostart.sh` so shell proxy hooks refresh both:
  - `/etc/profile.d/99-dl-research-toolbox-proxy.sh`
  - `~/.bashrc`
- Kept `~/.profile` profile fallback for containers without systemd.
- Added official `codex doctor --ascii --summary` to `scripts/doctor.sh` so
  the toolbox sees Codex's own connectivity/auth/runtime view.
- Restarted the stale app-server so it inherited the current proxy environment.
- Added `scripts/network-repair.sh` and `toolbox repair` for the common recovery
  bundle: refresh hooks, start mihomo, short-scan selectors, verify proxy
  egress, run Codex egress/doctor checks, configure Git HTTP/1.1 proxy, and
  inspect app-server proxy env.
- Added `toolbox repair app-server` as an explicit action for the disruptive
  app-server restart case.

## Correct Diagnostic Order

Run these from the target machine:

```bash
cd /root/autodl-tmp/projects/dl-research-toolbox
toolbox repair status
toolbox repair
toolbox check
codex login status
codex doctor --ascii --summary
printf '%s' 'Reply exactly OK' | codex exec --sandbox read-only --color never --skip-git-repo-check -
```

If `codex doctor` says provider endpoints or WebSocket are unreachable, run:

```bash
toolbox repair codex
```

If it says there are no proxy environment variables, open a new shell or run:

```bash
source scripts/proxy-on.sh
```

If an existing Codex TUI was started before the shell hook was fixed, exit it
and start a fresh process:

```bash
codex
```

If the app-server was started before the proxy fix, restart it explicitly:

```bash
toolbox repair app-server
```

## Prevention Rules

- On headless servers, prefer `codex login --device-auth`.
- Treat `codex doctor --ascii --summary` as the source of truth for Codex CLI
  runtime health.
- Do not run `codex login --device-auth` as a routine health check when Codex
  is already logged in.
- Do not conclude "node works" from `api.openai.com` alone. Test the Codex
  device-code endpoint path.
- Check the environment of already-running Codex processes when behavior differs
  between a fresh shell and an existing TUI.
- If proxy env exists but HTTPS egress fails with TLS EOF or TCP timeout, treat
  it as a bad active selector and run `toolbox repair` or `toolbox mihomo best`.
- Distinguish machine/network failures from account quota or plan limits. Once
  `codex doctor` passes and `codex exec` reaches the model service, quota errors
  are not fixed by switching proxy nodes.
