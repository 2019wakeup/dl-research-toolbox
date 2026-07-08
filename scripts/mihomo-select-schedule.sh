#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

ACTION="status"
MODE="${MIHOMO_SELECT_SCHEDULE_MODE:-auto}"
INTERVAL_HOURS="${MIHOMO_SELECT_SCHEDULE_INTERVAL_HOURS:-6}"
SELECT_LIMIT="${MIHOMO_SELECT_SCHEDULE_LIMIT:-40}"
SELECT_TIMEOUT="${MIHOMO_SELECT_SCHEDULE_TIMEOUT:-2500}"
CHECK_EGRESS=1
START_NOW=1
RUN_NOW=1
DRY_RUN=0

STATE_DIR="${MIHOMO_SELECT_SCHEDULE_STATE_DIR:-$HOME/.local/state/dl-research-toolbox}"
LOG_FILE="${MIHOMO_SELECT_SCHEDULE_LOG:-$STATE_DIR/mihomo-select-schedule.log}"
PID_FILE="$STATE_DIR/mihomo-select-schedule.pid"
LOCK_DIR="$STATE_DIR/mihomo-select-schedule.lock"
PROFILE_FILE="${MIHOMO_SELECT_SCHEDULE_PROFILE_FILE:-$HOME/.profile}"
BASHRC_FILE="${MIHOMO_SELECT_SCHEDULE_BASHRC_FILE:-$HOME/.bashrc}"
PROFILED_FILE="${MIHOMO_SELECT_SCHEDULE_PROFILED_FILE:-}"
USER_NAME="$(id -un)"
SERVICE_BASENAME="dl-research-mihomo-select"

usage() {
  cat <<'USAGE'
Usage: bash scripts/mihomo-select-schedule.sh [install|uninstall|status|run|start-loop|stop-loop|loop] [options]

Install or run hourly timed proxy node selection. This intentionally runs the
lightweight mihomo selection path only: start mihomo if needed, select a
reachable preferred node, and optionally verify proxy egress. It does not run
Codex login repair, git config changes, or app-server restarts.

Actions:
  install       Install a timer or loop. Default interval: 6 hours.
  uninstall     Remove timers/hooks and stop the fallback loop.
  status        Show installed timer/loop status. Default.
  run           Run one scheduled proxy selection immediately.
  start-loop    Start the fallback background loop.
  stop-loop     Stop the fallback background loop.
  loop          Internal foreground loop used by start-loop.

Options:
  --interval-hours N   Positive integer interval in hours. Default: 6.
  --mode auto|system|user|loop
                       Default: auto. Uses systemd user timer, system timer, or
                       profile-backed loop depending on host capabilities.
  --limit N            Mihomo selector probe limit. Default: 40.
  --timeout MS         Mihomo per-node delay timeout. Default: 2500.
  --no-check           Skip strict proxy egress check after selection.
  --no-start           Install but do not start timer/loop now.
  --no-run-now         Install timer/loop but do not run one selection now.
  --dry-run            Print planned changes without writing services/hooks.
  -h, --help           Show this help.

Environment:
  MIHOMO_SELECT_SCHEDULE_INTERVAL_HOURS
  MIHOMO_SELECT_SCHEDULE_MODE
  MIHOMO_SELECT_SCHEDULE_LIMIT
  MIHOMO_SELECT_SCHEDULE_TIMEOUT
  MIHOMO_SELECT_SCHEDULE_STATE_DIR
  MIHOMO_SELECT_SCHEDULE_LOG
USAGE
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    install|uninstall|status|run|start-loop|stop-loop|loop)
      ACTION="$1"
      shift
      ;;
  esac
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --interval-hours) INTERVAL_HOURS="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --limit) SELECT_LIMIT="${2:-}"; shift 2 ;;
    --timeout) SELECT_TIMEOUT="${2:-}"; shift 2 ;;
    --no-check) CHECK_EGRESS=0; shift ;;
    --no-start) START_NOW=0; shift ;;
    --no-run-now) RUN_NOW=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$INTERVAL_HOURS" in ''|*[!0-9]*) echo "--interval-hours must be a positive integer." >&2; exit 2 ;; esac
case "$SELECT_LIMIT" in ''|*[!0-9]*) echo "--limit must be a positive integer." >&2; exit 2 ;; esac
case "$SELECT_TIMEOUT" in ''|*[!0-9]*) echo "--timeout must be a positive integer." >&2; exit 2 ;; esac
[ "$INTERVAL_HOURS" -gt 0 ] || { echo "--interval-hours must be greater than 0." >&2; exit 2; }
[ "$SELECT_LIMIT" -gt 0 ] || SELECT_LIMIT=40
[ "$SELECT_TIMEOUT" -gt 0 ] || SELECT_TIMEOUT=2500

case "$MODE" in
  auto|system|user|loop) ;;
  *) echo "Invalid --mode: $MODE" >&2; exit 2 ;;
esac

if [ -z "$PROFILED_FILE" ] && [ "$(id -u)" -eq 0 ] && [ -d /etc/profile.d ]; then
  PROFILED_FILE="/etc/profile.d/99-dl-research-toolbox-mihomo-select-schedule.sh"
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

sudo_prefix() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    printf 'sudo\n'
    return 0
  fi
  return 1
}

systemd_system_available() {
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

systemd_user_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

can_install_system_timer() {
  systemd_system_available && { [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; }
}

system_unit_base() {
  printf '%s-%s\n' "$SERVICE_BASENAME" "$USER_NAME"
}

system_service_file() {
  printf '/etc/systemd/system/%s.service\n' "$(system_unit_base)"
}

system_timer_file() {
  printf '/etc/systemd/system/%s.timer\n' "$(system_unit_base)"
}

user_unit_base() {
  printf '%s\n' "$SERVICE_BASENAME"
}

user_unit_dir() {
  printf '%s\n' "$HOME/.config/systemd/user"
}

user_service_file() {
  printf '%s/%s.service\n' "$(user_unit_dir)" "$(user_unit_base)"
}

user_timer_file() {
  printf '%s/%s.timer\n' "$(user_unit_dir)" "$(user_unit_base)"
}

check_flag_args() {
  if [ "$CHECK_EGRESS" -eq 0 ]; then
    printf ' --no-check'
  fi
}

install_service_file() {
  local path="$1"
  local timer="$2"
  local mode_label="$3"
  local tmp user_line=""
  if [ "$mode_label" = "system timer" ]; then
    user_line="User=$USER_NAME"
  fi
  tmp="$(mktemp)"
  cat > "$tmp" <<SERVICE
[Unit]
Description=DL research timed proxy node selection ($mode_label)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
$user_line
Environment=HOME=$HOME
WorkingDirectory=$REPO_ROOT
ExecStart=/usr/bin/env bash $SCRIPT_DIR/mihomo-select-schedule.sh run --interval-hours $INTERVAL_HOURS --limit $SELECT_LIMIT --timeout $SELECT_TIMEOUT$(check_flag_args)
SERVICE

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] install -m 0644 $tmp $path"
    sed -n '1,120p' "$tmp"
  else
    install -m 0644 "$tmp" "$path"
  fi
  rm -f "$tmp"

  tmp="$(mktemp)"
  cat > "$tmp" <<TIMER
[Unit]
Description=Run DL research proxy node selection every $INTERVAL_HOURS hour(s)

[Timer]
OnBootSec=5min
OnUnitActiveSec=${INTERVAL_HOURS}h
Persistent=true
Unit=$(basename "$path")

[Install]
WantedBy=timers.target
TIMER

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] install -m 0644 $tmp $timer"
    sed -n '1,120p' "$tmp"
  else
    install -m 0644 "$tmp" "$timer"
  fi
  rm -f "$tmp"
}

install_user_timer() {
  if ! systemd_user_available; then
    echo "systemd user manager is unavailable." >&2
    exit 1
  fi
  run mkdir -p "$(user_unit_dir)"
  install_service_file "$(user_service_file)" "$(user_timer_file)" "user timer"
  run systemctl --user daemon-reload
  if [ "$START_NOW" -eq 1 ]; then
    run systemctl --user enable --now "$(basename "$(user_timer_file)")"
    if [ "$RUN_NOW" -eq 1 ]; then
      run systemctl --user start "$(basename "$(user_service_file)")" || true
    fi
  else
    run systemctl --user enable "$(basename "$(user_timer_file)")"
  fi
  echo "Installed user timer: $(user_timer_file)"
}

install_system_timer() {
  if ! can_install_system_timer; then
    echo "systemd system manager or sudo/root access is unavailable." >&2
    exit 1
  fi
  local sudo_cmd=""
  sudo_cmd="$(sudo_prefix || true)"
  local service timer tmp_dir
  service="$(system_service_file)"
  timer="$(system_timer_file)"
  if [ -n "$sudo_cmd" ]; then
    tmp_dir="$(mktemp -d)"
    install_service_file "$tmp_dir/$(basename "$service")" "$tmp_dir/$(basename "$timer")" "system timer"
    run sudo install -m 0644 "$tmp_dir/$(basename "$service")" "$service"
    run sudo install -m 0644 "$tmp_dir/$(basename "$timer")" "$timer"
    rm -rf "$tmp_dir"
    run sudo systemctl daemon-reload
    if [ "$START_NOW" -eq 1 ]; then
      run sudo systemctl enable --now "$(basename "$timer")"
      if [ "$RUN_NOW" -eq 1 ]; then
        run sudo systemctl start "$(basename "$service")" || true
      fi
    else
      run sudo systemctl enable "$(basename "$timer")"
    fi
  else
    install_service_file "$service" "$timer" "system timer"
    run systemctl daemon-reload
    if [ "$START_NOW" -eq 1 ]; then
      run systemctl enable --now "$(basename "$timer")"
      if [ "$RUN_NOW" -eq 1 ]; then
        run systemctl start "$(basename "$service")" || true
      fi
    else
      run systemctl enable "$(basename "$timer")"
    fi
  fi
  echo "Installed system timer: $timer"
}

remove_marked_block() {
  local file="$1"
  local start="$2"
  local end="$3"
  if [ ! -f "$file" ]; then
    return 0
  fi
  python3 - "$file" "$start" "$end" <<'PY_REMOVE_MARKED_BLOCK'
from pathlib import Path
import sys

p = Path(sys.argv[1])
start = sys.argv[2]
end = sys.argv[3]
s = p.read_text()
changed = False
while start in s and end in s:
    a = s.index(start)
    b = s.index(end, a) + len(end)
    if a > 0 and s[a - 1] == "\n":
        a -= 1
    if b < len(s) and s[b:b+1] == "\n":
        b += 1
    s = s[:a] + s[b:]
    changed = True
if changed:
    p.write_text(s)
PY_REMOVE_MARKED_BLOCK
}

hook_body() {
  cat <<HOOK
# Keep dl-research-toolbox timed proxy node selection alive when no service manager exists.
DL_RESEARCH_TOOLBOX_DIR="$REPO_ROOT"
for _dl_toolbox_dir in "\$DL_RESEARCH_TOOLBOX_DIR" "\$HOME/autodl-tmp/projects/dl-research-toolbox" "\$HOME/dl-research-toolbox"; do
  if [ -x "\$_dl_toolbox_dir/scripts/mihomo-select-schedule.sh" ]; then
    DL_RESEARCH_TOOLBOX_DIR="\$_dl_toolbox_dir"
    break
  fi
done

if [ -x "\$DL_RESEARCH_TOOLBOX_DIR/scripts/mihomo-select-schedule.sh" ]; then
  bash "\$DL_RESEARCH_TOOLBOX_DIR/scripts/mihomo-select-schedule.sh" start-loop --interval-hours "$INTERVAL_HOURS" --limit "$SELECT_LIMIT" --timeout "$SELECT_TIMEOUT"$(check_flag_args) >/dev/null 2>&1 || true
fi

unset _dl_toolbox_dir DL_RESEARCH_TOOLBOX_DIR
HOOK
}

hook_block() {
  cat <<HOOK
# >>> dl-research-toolbox mihomo select schedule >>>
$(hook_body)
# <<< dl-research-toolbox mihomo select schedule <<<
HOOK
}

install_loop_hook() {
  if [ -n "$PROFILED_FILE" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] write mihomo select schedule profile hook: $PROFILED_FILE"
    else
      mkdir -p "$(dirname "$PROFILED_FILE")"
      hook_block > "$PROFILED_FILE"
      chmod 0644 "$PROFILED_FILE"
    fi
    echo "Installed/refreshed mihomo select schedule hook: $PROFILED_FILE"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] refresh mihomo select schedule bashrc hook: $BASHRC_FILE"
    return 0
  fi
  touch "$BASHRC_FILE"
  remove_marked_block "$BASHRC_FILE" '# >>> dl-research-toolbox mihomo select schedule >>>' '# <<< dl-research-toolbox mihomo select schedule <<<'
  {
    printf '\n'
    hook_block
  } >> "$BASHRC_FILE"
  echo "Installed/refreshed mihomo select schedule bashrc hook: $BASHRC_FILE"
}

remove_loop_hook() {
  if [ -n "$PROFILED_FILE" ] && [ -f "$PROFILED_FILE" ] && grep -Fq 'dl-research-toolbox mihomo select schedule' "$PROFILED_FILE"; then
    run rm -f "$PROFILED_FILE"
    echo "Removed mihomo select schedule hook: $PROFILED_FILE"
  elif [ -n "$PROFILED_FILE" ]; then
    echo "Mihomo select schedule hook missing from: $PROFILED_FILE"
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] remove mihomo select schedule bashrc hook: $BASHRC_FILE"
  else
    remove_marked_block "$BASHRC_FILE" '# >>> dl-research-toolbox mihomo select schedule >>>' '# <<< dl-research-toolbox mihomo select schedule <<<'
    echo "Removed mihomo select schedule bashrc hook from: $BASHRC_FILE"
  fi
}

loop_is_running() {
  local pid
  if [ ! -f "$PID_FILE" ]; then
    return 1
  fi
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

start_loop() {
  run mkdir -p "$STATE_DIR"
  if loop_is_running; then
    echo "Fallback loop already running: pid=$(cat "$PID_FILE")"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] nohup bash $SCRIPT_DIR/mihomo-select-schedule.sh loop --interval-hours $INTERVAL_HOURS --limit $SELECT_LIMIT --timeout $SELECT_TIMEOUT$(check_flag_args)"
    return 0
  fi
  nohup bash "$SCRIPT_DIR/mihomo-select-schedule.sh" loop \
    --interval-hours "$INTERVAL_HOURS" \
    --limit "$SELECT_LIMIT" \
    --timeout "$SELECT_TIMEOUT" \
    $(check_flag_args) >/dev/null 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$PID_FILE"
  echo "Started fallback loop: pid=$(cat "$PID_FILE") interval=${INTERVAL_HOURS}h"
}

stop_loop() {
  local pid
  if ! loop_is_running; then
    echo "Fallback loop is not running."
    run rm -f "$PID_FILE"
    return 0
  fi
  pid="$(cat "$PID_FILE")"
  run kill "$pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    run kill -9 "$pid" 2>/dev/null || true
  fi
  run rm -f "$PID_FILE"
  echo "Stopped fallback loop: pid=$pid"
}

run_once() (
  cd "$REPO_ROOT"
  mkdir -p "$STATE_DIR"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    {
      printf '[%s] scheduled proxy selection skipped: another run is active\n' "$(date -Is)"
    } | tee -a "$LOG_FILE"
    exit 0
  fi
  trap 'rm -rf "$LOCK_DIR"' EXIT

  {
    printf '\n[%s] scheduled proxy selection start interval_hours=%s limit=%s timeout_ms=%s\n' "$(date -Is)" "$INTERVAL_HOURS" "$SELECT_LIMIT" "$SELECT_TIMEOUT"
    bash scripts/mihomo-start.sh || true
    if [ -f scripts/proxy-on.sh ]; then
      # shellcheck disable=SC1091
      source scripts/proxy-on.sh >/dev/null
    fi
    if ! bash scripts/mihomo-select-best.sh --timeout "$SELECT_TIMEOUT" --limit "$SELECT_LIMIT"; then
      echo "selector scan failed; restarting mihomo and retrying once" >&2
      bash scripts/mihomo-stop.sh || true
      bash scripts/mihomo-start.sh
      if [ -f scripts/proxy-on.sh ]; then
        # shellcheck disable=SC1091
        source scripts/proxy-on.sh >/dev/null
      fi
      bash scripts/mihomo-select-best.sh --timeout "$SELECT_TIMEOUT" --limit "$SELECT_LIMIT"
    fi
    if [ "$CHECK_EGRESS" -eq 1 ]; then
      bash scripts/mihomo-status.sh --strict --test-proxy --no-log
    fi
    printf '[%s] scheduled proxy selection complete\n' "$(date -Is)"
  } 2>&1 | tee -a "$LOG_FILE"
)

run_loop() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$$" > "$PID_FILE"
  trap 'rm -f "$PID_FILE"' EXIT
  while true; do
    run_once || true
    sleep "$((INTERVAL_HOURS * 3600))"
  done
}

install_loop() {
  install_loop_hook
  if [ "$START_NOW" -eq 1 ]; then
    start_loop
    if [ "$RUN_NOW" -eq 1 ]; then
      run_once || true
    fi
  fi
  echo "Installed fallback loop schedule: interval=${INTERVAL_HOURS}h"
}

install_schedule() {
  case "$MODE" in
    user) install_user_timer ;;
    system) install_system_timer ;;
    loop) install_loop ;;
    auto)
      if systemd_user_available; then
        install_user_timer
      elif can_install_system_timer; then
        install_system_timer
      else
        echo "systemd timer unavailable; using profile-backed fallback loop."
        install_loop
      fi
      ;;
  esac
}

uninstall_user_timer() {
  if systemd_user_available; then
    run systemctl --user disable --now "$(basename "$(user_timer_file)")" >/dev/null 2>&1 || true
    run systemctl --user daemon-reload || true
  fi
  run rm -f "$(user_service_file)" "$(user_timer_file)"
  echo "Removed user timer files."
}

uninstall_system_timer() {
  local sudo_cmd=""
  sudo_cmd="$(sudo_prefix || true)"
  if [ -z "$sudo_cmd" ] && [ "$(id -u)" -ne 0 ]; then
    echo "Skipping system timer removal: root/sudo access is unavailable."
    return 0
  fi
  if systemd_system_available; then
    if [ -n "$sudo_cmd" ]; then
      run sudo systemctl disable --now "$(basename "$(system_timer_file)")" >/dev/null 2>&1 || true
      run sudo rm -f "$(system_service_file)" "$(system_timer_file)"
      run sudo systemctl daemon-reload || true
    else
      run systemctl disable --now "$(basename "$(system_timer_file)")" >/dev/null 2>&1 || true
      run rm -f "$(system_service_file)" "$(system_timer_file)"
      run systemctl daemon-reload || true
    fi
  else
    if [ -n "$sudo_cmd" ]; then
      run sudo rm -f "$(system_service_file)" "$(system_timer_file)"
    else
      run rm -f "$(system_service_file)" "$(system_timer_file)"
    fi
  fi
  echo "Removed system timer files."
}

uninstall_schedule() {
  uninstall_user_timer
  uninstall_system_timer
  stop_loop || true
  remove_loop_hook
}

show_status() {
  echo "Timed proxy selection status"
  echo "----------------------------"
  echo "interval_hours: $INTERVAL_HOURS"
  echo "mode: $MODE"
  echo "state_dir: $STATE_DIR"
  echo "log_file: $LOG_FILE"
  echo

  echo "systemd user timer"
  if [ -f "$(user_timer_file)" ]; then echo "file: $(user_timer_file)"; else echo "file: missing"; fi
  if systemd_user_available; then
    systemctl --user is-enabled "$(basename "$(user_timer_file)")" 2>/dev/null || true
    systemctl --user --no-pager --full status "$(basename "$(user_timer_file)")" 2>/dev/null | sed -n '1,12p' || true
  else
    echo "systemd user manager: unavailable"
  fi
  echo

  echo "systemd system timer"
  if [ -f "$(system_timer_file)" ]; then echo "file: $(system_timer_file)"; else echo "file: missing"; fi
  if systemd_system_available; then
    systemctl is-enabled "$(basename "$(system_timer_file)")" 2>/dev/null || true
    systemctl --no-pager --full status "$(basename "$(system_timer_file)")" 2>/dev/null | sed -n '1,12p' || true
  else
    echo "systemd system manager: unavailable"
  fi
  echo

  echo "fallback loop"
  if loop_is_running; then
    echo "loop: running pid=$(cat "$PID_FILE")"
  else
    echo "loop: not running"
  fi
  if [ -n "$PROFILED_FILE" ] && [ -f "$PROFILED_FILE" ] && grep -Fq 'dl-research-toolbox mihomo select schedule' "$PROFILED_FILE"; then
    echo "profile.d hook: installed in $PROFILED_FILE"
  elif [ -n "$PROFILED_FILE" ]; then
    echo "profile.d hook: missing from $PROFILED_FILE"
  else
    echo "profile.d hook: unavailable"
  fi
  if [ -f "$BASHRC_FILE" ] && grep -Fq 'dl-research-toolbox mihomo select schedule' "$BASHRC_FILE"; then
    echo "bashrc hook: installed in $BASHRC_FILE"
  else
    echo "bashrc hook: missing from $BASHRC_FILE"
  fi
  echo

  if [ -f "$LOG_FILE" ]; then
    echo "recent log"
    tail -n 30 "$LOG_FILE" || true
  else
    echo "recent log: missing"
  fi
}

case "$ACTION" in
  install) install_schedule ;;
  uninstall) uninstall_schedule ;;
  status) show_status ;;
  run) run_once ;;
  start-loop) start_loop ;;
  stop-loop) stop_loop ;;
  loop) run_loop ;;
  *)
    echo "Unknown action: $ACTION" >&2
    usage >&2
    exit 2
    ;;
esac
