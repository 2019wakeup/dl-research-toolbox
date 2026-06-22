#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

ACTION="all"
if [ "$#" -gt 0 ]; then
  case "$1" in
    all|quick|status|proxy|codex|git|app-server|appserver)
      ACTION="$1"
      shift
      ;;
  esac
fi

STRICT=1
RUN_CODEX_DOCTOR=1
RUN_GIT_REPAIR=1
RESTART_APP_SERVER=0
SELECT_LIMIT="${NETWORK_REPAIR_SELECT_LIMIT:-40}"
SELECT_TIMEOUT="${NETWORK_REPAIR_SELECT_TIMEOUT:-2500}"
CODEX_SCAN_LIMIT="${NETWORK_REPAIR_CODEX_SCAN_LIMIT:-40}"
GIT_REPO="${TOOLBOX_CALLER_CWD:-$REPO_ROOT}"
FAILURES=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/network-repair.sh [all|status|proxy|codex|git|app-server] [options]

Common network recovery commands for mihomo, Codex, app-server, and Git.

Actions:
  all          Repair mihomo/autostart, Codex egress, and Git proxy config. Default.
  status       Print current proxy, Codex, app-server, and Git status.
  proxy        Refresh autostart hooks, start mihomo, select a reachable node, and test egress.
  codex        Run proxy repair, Codex login-egress repair, and official codex doctor.
  git          Configure the selected Git repo for local proxy and HTTP/1.1.
  app-server   Restart Codex app-server processes so they inherit current proxy env.

Options:
  --limit N          Mihomo selector probe limit for fast repair. Default: 40.
  --timeout MS       Mihomo per-node delay timeout. Default: 2500.
  --codex-scan N     Codex login-egress repair scan limit. Default: 40.
  --repo DIR         Git repo for the git repair action. Default: caller cwd if it is a repo.
  --restart-app-server  Also restart Codex app-server during the all action.
  --no-codex-doctor  Skip official `codex doctor --ascii --summary`.
  --no-git           Skip Git proxy config during the all action.
  --deep             Use broader selector and Codex scans.
  --no-strict        Print failures but exit zero.
  -h, --help         Show this help.

Environment:
  NETWORK_REPAIR_SELECT_LIMIT
  NETWORK_REPAIR_SELECT_TIMEOUT
  NETWORK_REPAIR_CODEX_SCAN_LIMIT
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --limit) SELECT_LIMIT="${2:-}"; shift 2 ;;
    --timeout) SELECT_TIMEOUT="${2:-}"; shift 2 ;;
    --codex-scan) CODEX_SCAN_LIMIT="${2:-}"; shift 2 ;;
    --repo) GIT_REPO="${2:-}"; shift 2 ;;
    --restart-app-server) RESTART_APP_SERVER=1; shift ;;
    --no-codex-doctor) RUN_CODEX_DOCTOR=0; shift ;;
    --no-git) RUN_GIT_REPAIR=0; shift ;;
    --deep)
      SELECT_LIMIT=120
      SELECT_TIMEOUT=5000
      CODEX_SCAN_LIMIT=120
      shift
      ;;
    --no-strict) STRICT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$SELECT_LIMIT" in ''|*[!0-9]*) echo "--limit must be a positive integer." >&2; exit 2 ;; esac
case "$SELECT_TIMEOUT" in ''|*[!0-9]*) echo "--timeout must be a positive integer." >&2; exit 2 ;; esac
case "$CODEX_SCAN_LIMIT" in ''|*[!0-9]*) echo "--codex-scan must be a positive integer." >&2; exit 2 ;; esac

cd "$REPO_ROOT"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

banner() {
  local title="$1"
  local rule="========================================================================"
  echo
  echo "$rule"
  echo "REPAIR: $title"
  echo "$rule"
}

mark_failure() {
  FAILURES=$((FAILURES + 1))
}

redact_value() {
  sed -E 's#(https?://)[^/@]+@#\1[redacted]@#; s#(socks[0-9a-zA-Z]*://)[^/@]+@#\1[redacted]@#'
}

source_proxy() {
  if [ -f scripts/proxy-on.sh ]; then
    # shellcheck disable=SC1091
    source scripts/proxy-on.sh >/dev/null
  fi
}

run_or_mark() {
  local label="$1"
  shift
  banner "$label"
  if "$@"; then
    echo "[ok] $label"
  else
    echo "[fail] $label" >&2
    mark_failure
    return 1
  fi
}

show_proxy_env() {
  env | grep -Ei '^(http|https|all|no)_proxy=' | sort | redact_value || true
}

codex_app_server_pids() {
  ps -eo pid=,args= | awk '/[c]odex app-server/ {print $1}'
}

inspect_app_server() {
  local pid env_lines missing=0 found=0
  mapfile -t pids < <(codex_app_server_pids || true)
  if [ "${#pids[@]}" -eq 0 ]; then
    echo "No codex app-server process is running."
    return 0
  fi

  for pid in "${pids[@]}"; do
    found=1
    echo "pid=$pid"
    if [ -r "/proc/$pid/environ" ]; then
      env_lines="$(tr '\0' '\n' < "/proc/$pid/environ" | grep -Ei '^(http|https|all|no)_proxy=' | sort | redact_value || true)"
      if [ -n "$env_lines" ]; then
        echo "$env_lines" | sed 's/^/  /'
      else
        echo "  proxy env: missing"
        missing=1
      fi
    else
      echo "  proxy env: cannot read /proc/$pid/environ"
    fi
  done

  [ "$found" -eq 1 ] && [ "$missing" -eq 0 ]
}

status_action() {
  banner "mihomo and autostart status"
  bash scripts/mihomo-autostart.sh status || mark_failure

  banner "current shell proxy env"
  show_proxy_env

  banner "Codex login and doctor"
  if command -v codex >/dev/null 2>&1; then
    codex login status || true
    if [ "$RUN_CODEX_DOCTOR" -eq 1 ]; then
      source_proxy
      codex doctor --ascii --summary || mark_failure
    fi
  else
    echo "codex not found on PATH" >&2
    mark_failure
  fi

  banner "Codex app-server proxy env"
  inspect_app_server || mark_failure

  banner "Git proxy config"
  show_git_config || true
}

repair_proxy() {
  banner "refresh autostart and shell proxy hooks"
  bash scripts/mihomo-autostart.sh install --mode auto --enable-linger

  banner "start mihomo"
  bash scripts/mihomo-start.sh || true
  source_proxy

  banner "select reachable mihomo node"
  if ! bash scripts/mihomo-select-best.sh --timeout "$SELECT_TIMEOUT" --limit "$SELECT_LIMIT"; then
    echo "first selector scan failed; restarting mihomo and retrying once" >&2
    bash scripts/mihomo-stop.sh || true
    bash scripts/mihomo-start.sh
    source_proxy
    bash scripts/mihomo-select-best.sh --timeout "$SELECT_TIMEOUT" --limit "$SELECT_LIMIT"
  fi

  banner "verify proxy egress"
  bash scripts/mihomo-status.sh --strict --test-proxy --no-log
}

repair_codex() {
  source_proxy

  banner "Codex login status"
  if command -v codex >/dev/null 2>&1; then
    codex login status || true
  else
    echo "codex not found on PATH" >&2
    return 1
  fi

  banner "Codex login egress"
  bash scripts/codex-login-egress-check.sh repair --no-source-proxy --scan-limit "$CODEX_SCAN_LIMIT"

  if [ "$RUN_CODEX_DOCTOR" -eq 1 ]; then
    banner "official Codex doctor"
    codex doctor --ascii --summary
  fi
}

resolve_git_repo() {
  local repo="$GIT_REPO"
  if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$repo" rev-parse --show-toplevel
    return 0
  fi
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$REPO_ROOT" rev-parse --show-toplevel
    return 0
  fi
  return 1
}

show_git_config() {
  local repo
  repo="$(resolve_git_repo)" || {
    echo "No Git repository found for caller cwd or toolbox root."
    return 0
  }
  echo "repo: $repo"
  git -C "$repo" config --local --get http.version 2>/dev/null | sed 's/^/http.version: /' || true
  git -C "$repo" config --local --get http.proxy 2>/dev/null | redact_value | sed 's/^/http.proxy: /' || true
  git -C "$repo" config --local --get https.proxy 2>/dev/null | redact_value | sed 's/^/https.proxy: /' || true
}

repair_git() {
  local repo proxy_url origin_url
  repo="$(resolve_git_repo)" || {
    echo "No Git repository found for caller cwd or toolbox root." >&2
    return 1
  }
  source_proxy
  proxy_url="${http_proxy:-http://127.0.0.1:7890}"

  banner "configure Git proxy"
  echo "repo: $repo"
  git -C "$repo" config --local http.version HTTP/1.1
  git -C "$repo" config --local http.proxy "$proxy_url"
  git -C "$repo" config --local https.proxy "$proxy_url"
  show_git_config

  origin_url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  if [ -n "$origin_url" ]; then
    banner "test Git origin reachability"
    if git -C "$repo" ls-remote --heads origin >/dev/null; then
      echo "[ok] origin reachable"
    else
      echo "[warn] origin reachability test failed; Git proxy config was still applied"
    fi
  fi
}

restart_app_server() {
  local pids pid control_dir
  mapfile -t pids < <(codex_app_server_pids || true)
  banner "restart Codex app-server"
  if [ "${#pids[@]}" -gt 0 ]; then
    echo "stopping pids: ${pids[*]}"
    for pid in "${pids[@]}"; do
      kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 1
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    done
  else
    echo "no existing app-server process found"
  fi

  control_dir="$HOME/.codex/app-server-control"
  mkdir -p "$control_dir"
  rm -f "$control_dir/app-server-control.sock" "$control_dir/desktop-ssh-websocket-v0.sock"

  source_proxy
  if command -v codex >/dev/null 2>&1; then
    nohup codex app-server --listen unix:// > "$control_dir/app-server.log" 2>&1 < /dev/null &
    sleep 2
    inspect_app_server
  else
    echo "codex not found on PATH" >&2
    return 1
  fi
}

run_action() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "[fail] $label" >&2
    mark_failure
  else
    echo "[ok] $label"
  fi
}

case "$ACTION" in
  all|quick)
    run_action "proxy repair" repair_proxy
    run_action "Codex repair" repair_codex
    if [ "$RUN_GIT_REPAIR" -eq 1 ]; then
      run_action "Git repair" repair_git
    fi
    if [ "$RESTART_APP_SERVER" -eq 1 ]; then
      run_action "Codex app-server restart" restart_app_server
    else
      run_or_mark "Codex app-server proxy env" inspect_app_server || true
    fi
    ;;
  status)
    status_action
    ;;
  proxy)
    run_action "proxy repair" repair_proxy
    ;;
  codex)
    run_action "proxy repair" repair_proxy
    run_action "Codex repair" repair_codex
    ;;
  git)
    run_action "Git repair" repair_git
    ;;
  app-server|appserver)
    run_action "Codex app-server restart" restart_app_server
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    usage >&2
    exit 2
    ;;
esac

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "Network repair checks passed."
else
  echo "Network repair finished with $FAILURES issue(s)." >&2
fi

if [ "$STRICT" -eq 1 ] && [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
