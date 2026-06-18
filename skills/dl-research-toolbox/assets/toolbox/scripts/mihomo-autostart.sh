#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ACTION="install"
MODE="auto"
START_NOW=1
ENABLE_LINGER=0
AUTO_PROXY_ENV=1
SERVICE_BASENAME="dl-research-mihomo"
PROFILE_FILE="${MIHOMO_PROFILE_FILE:-$HOME/.profile}"
BASHRC_FILE="${MIHOMO_BASHRC_FILE:-$HOME/.bashrc}"
PROFILED_FILE="${MIHOMO_PROFILED_FILE:-}"
USER_NAME="$(id -un)"
MIHOMO_BIN="${MIHOMO_BIN:-$HOME/.local/bin/mihomo}"
MIHOMO_CONFIG_DIR="${MIHOMO_CONFIG_DIR:-$HOME/.config/mihomo}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/mihomo-autostart.sh [install|uninstall|status] [options]

Install or remove mihomo autostart. Use system mode for true boot autostart,
user mode for systemd user service, and profile mode for container fallback.

Actions:
  install                    Install autostart. Default.
  uninstall                  Remove autostart entries.
  status                     Show autostart and mihomo status.

Options:
  --mode auto|system|user|profile  Default: auto.
  --no-start                       Install but do not start mihomo now.
  --enable-linger                  Enable linger for systemd user mode.
  --no-shell-env                   Do not install automatic shell proxy env hooks.
  -h, --help                       Show this help.

Examples:
  bash scripts/mihomo-autostart.sh install --mode system
  bash scripts/mihomo-autostart.sh install --mode user --enable-linger
  bash scripts/mihomo-autostart.sh install --mode profile
  bash scripts/mihomo-autostart.sh status
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    install|uninstall|status) ACTION="$1"; shift ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --no-start) START_NOW=0; shift ;;
    --enable-linger) ENABLE_LINGER=1; shift ;;
    --no-shell-env) AUTO_PROXY_ENV=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in
  auto|system|user|profile) ;;
  *) echo "Invalid --mode: $MODE" >&2; exit 2 ;;
esac

if [ -z "$PROFILED_FILE" ] && [ "$(id -u)" -eq 0 ] && [ -d /etc/profile.d ]; then
  PROFILED_FILE="/etc/profile.d/99-dl-research-toolbox-proxy.sh"
fi

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required for system autostart when not running as root." >&2
    exit 1
  fi
  printf 'sudo\n'
}

systemd_system_available() {
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

systemd_user_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

can_install_system_service() {
  systemd_system_available && { [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; }
}

system_service_name() {
  printf '%s-%s.service\n' "$SERVICE_BASENAME" "$USER_NAME"
}

system_service_file() {
  printf '/etc/systemd/system/%s\n' "$(system_service_name)"
}

user_service_name() {
  printf 'mihomo.service\n'
}

user_service_dir() {
  printf '%s\n' "$HOME/.config/systemd/user"
}

user_service_file() {
  printf '%s/%s\n' "$(user_service_dir)" "$(user_service_name)"
}

require_mihomo_ready() {
  if [ ! -x "$MIHOMO_BIN" ]; then
    echo "mihomo binary is missing or not executable: $MIHOMO_BIN" >&2
    echo "Run: bash scripts/mihomo-install.sh" >&2
    exit 1
  fi
  if [ ! -f "$MIHOMO_CONFIG_DIR/config.yaml" ]; then
    echo "mihomo config is missing: $MIHOMO_CONFIG_DIR/config.yaml" >&2
    echo "Run: bash scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml" >&2
    exit 1
  fi
}

install_system_service() {
  require_mihomo_ready
  if ! systemd_system_available; then
    echo "systemd system manager is unavailable." >&2
    exit 1
  fi

  local svc tmp sudo_prefix
  svc="$(system_service_name)"
  tmp="$(mktemp)"
  sudo_prefix="$(sudo_cmd || true)"
  cat > "$tmp" <<SERVICE
[Unit]
Description=DL research mihomo proxy for $USER_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER_NAME
Environment=HOME=$HOME
ExecStart=$MIHOMO_BIN -d $MIHOMO_CONFIG_DIR
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

  if [ -n "$sudo_prefix" ]; then
    sudo install -m 0644 "$tmp" "$(system_service_file)"
    sudo systemctl daemon-reload
    sudo systemctl enable "$svc"
    if [ "$START_NOW" -eq 1 ]; then sudo systemctl restart "$svc"; fi
  else
    install -m 0644 "$tmp" "$(system_service_file)"
    systemctl daemon-reload
    systemctl enable "$svc"
    if [ "$START_NOW" -eq 1 ]; then systemctl restart "$svc"; fi
  fi
  rm -f "$tmp"
  echo "Installed system service: $(system_service_file)"
}

uninstall_system_service() {
  local svc sudo_prefix
  svc="$(system_service_name)"
  sudo_prefix="$(sudo_cmd || true)"
  if systemd_system_available; then
    if [ -n "$sudo_prefix" ]; then
      sudo systemctl disable --now "$svc" >/dev/null 2>&1 || true
      sudo rm -f "$(system_service_file)"
      sudo systemctl daemon-reload || true
    else
      systemctl disable --now "$svc" >/dev/null 2>&1 || true
      rm -f "$(system_service_file)"
      systemctl daemon-reload || true
    fi
  else
    if [ -n "$sudo_prefix" ]; then sudo rm -f "$(system_service_file)"; else rm -f "$(system_service_file)"; fi
  fi
  echo "Removed system service: $(system_service_file)"
}

install_user_service() {
  require_mihomo_ready
  if ! systemd_user_available; then
    echo "systemd user manager is unavailable." >&2
    exit 1
  fi

  mkdir -p "$(user_service_dir)"
  cat > "$(user_service_file)" <<SERVICE
[Unit]
Description=User mihomo proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$MIHOMO_BIN -d $MIHOMO_CONFIG_DIR
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
SERVICE

  systemctl --user daemon-reload
  systemctl --user enable "$(user_service_name)"
  if [ "$START_NOW" -eq 1 ]; then systemctl --user restart "$(user_service_name)"; fi

  if [ "$ENABLE_LINGER" -eq 1 ]; then
    if command -v loginctl >/dev/null 2>&1; then
      loginctl enable-linger "$USER_NAME" || true
    else
      echo "loginctl not found; cannot enable linger." >&2
    fi
  fi
  echo "Installed systemd user service: $(user_service_file)"
}

uninstall_user_service() {
  if systemd_user_available; then
    systemctl --user disable --now "$(user_service_name)" >/dev/null 2>&1 || true
    systemctl --user daemon-reload || true
  fi
  rm -f "$(user_service_file)"
  echo "Removed systemd user service: $(user_service_file)"
}

shell_hook_body() {
  cat <<PROFILE
# Keep dl-research-toolbox mihomo and proxy variables available for Codex/research shells.
DL_RESEARCH_TOOLBOX_DIR="$REPO_ROOT"
for _dl_toolbox_dir in "\$DL_RESEARCH_TOOLBOX_DIR" "\$HOME/autodl-tmp/projects/dl-research-toolbox" "\$HOME/dl-research-toolbox"; do
  if [ -x "\$_dl_toolbox_dir/scripts/mihomo-start.sh" ]; then
    DL_RESEARCH_TOOLBOX_DIR="\$_dl_toolbox_dir"
    break
  fi
done

if [ -x "\$DL_RESEARCH_TOOLBOX_DIR/scripts/mihomo-start.sh" ]; then
  bash "\$DL_RESEARCH_TOOLBOX_DIR/scripts/mihomo-start.sh" >/dev/null 2>&1 || true
fi

if [ -f "\$DL_RESEARCH_TOOLBOX_DIR/scripts/proxy-on.sh" ]; then
  . "\$DL_RESEARCH_TOOLBOX_DIR/scripts/proxy-on.sh" >/dev/null 2>&1 || true
else
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  export HTTP_PROXY="http://127.0.0.1:7890"
  export HTTPS_PROXY="http://127.0.0.1:7890"
  export all_proxy="http://127.0.0.1:7890"
  export ALL_PROXY="http://127.0.0.1:7890"
  export no_proxy="localhost,127.0.0.1,::1"
  export NO_PROXY="localhost,127.0.0.1,::1"
fi

unset _dl_toolbox_dir DL_RESEARCH_TOOLBOX_DIR
PROFILE
}

profile_block() {
  cat <<PROFILE
# >>> dl-research-toolbox mihomo autostart >>>
$(shell_hook_body)
# <<< dl-research-toolbox mihomo autostart <<<
PROFILE
}

profiled_block() {
  cat <<PROFILED
# >>> dl-research-toolbox shell proxy hook >>>
$(shell_hook_body)
# <<< dl-research-toolbox shell proxy hook <<<
PROFILED
}

bashrc_block() {
  cat <<BASHRC
# >>> dl-research-toolbox bashrc proxy hook >>>
$(shell_hook_body)
# <<< dl-research-toolbox bashrc proxy hook <<<
BASHRC
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
    if a > 0 and s[a - 1] == '\n':
        a -= 1
    if b < len(s) and s[b:b+1] == '\n':
        b += 1
    s = s[:a] + s[b:]
    changed = True
if changed:
    p.write_text(s)
PY_REMOVE_MARKED_BLOCK
}

install_profile_hook() {
  require_mihomo_ready
  touch "$PROFILE_FILE"
  remove_marked_block "$PROFILE_FILE" '# >>> dl-research-toolbox mihomo autostart >>>' '# <<< dl-research-toolbox mihomo autostart <<<'
  {
    printf '\n'
    profile_block
  } >> "$PROFILE_FILE"
  echo "Installed/refreshed profile autostart hook: $PROFILE_FILE"
  if [ "$START_NOW" -eq 1 ]; then bash "$SCRIPT_DIR/mihomo-start.sh"; fi
}

uninstall_profile_hook() {
  remove_marked_block "$PROFILE_FILE" '# >>> dl-research-toolbox mihomo autostart >>>' '# <<< dl-research-toolbox mihomo autostart <<<'
  echo "Removed profile autostart hook from: $PROFILE_FILE"
}

install_shell_env_hook() {
  if [ "$AUTO_PROXY_ENV" -eq 0 ]; then
    echo "Skipping shell proxy env hooks (--no-shell-env)."
    return 0
  fi
  if [ -n "$PROFILED_FILE" ]; then
    mkdir -p "$(dirname "$PROFILED_FILE")"
    profiled_block > "$PROFILED_FILE"
    chmod 0644 "$PROFILED_FILE"
    echo "Installed/refreshed shell proxy env hook: $PROFILED_FILE"
  else
    echo "Skipping shell proxy env hook: /etc/profile.d is unavailable or not writable by this user."
  fi
  touch "$BASHRC_FILE"
  remove_marked_block "$BASHRC_FILE" '# >>> dl-research-toolbox bashrc proxy hook >>>' '# <<< dl-research-toolbox bashrc proxy hook <<<'
  {
    printf '\n'
    bashrc_block
  } >> "$BASHRC_FILE"
  echo "Installed/refreshed bashrc proxy hook: $BASHRC_FILE"
}

uninstall_shell_env_hook() {
  if [ -n "$PROFILED_FILE" ] && [ -f "$PROFILED_FILE" ] && grep -Fq 'dl-research-toolbox shell proxy hook' "$PROFILED_FILE"; then
    rm -f "$PROFILED_FILE"
    echo "Removed shell proxy env hook: $PROFILED_FILE"
  elif [ -n "$PROFILED_FILE" ]; then
    echo "Shell proxy env hook missing from: $PROFILED_FILE"
  else
    echo "Shell proxy env hook path unavailable."
  fi
  remove_marked_block "$BASHRC_FILE" '# >>> dl-research-toolbox bashrc proxy hook >>>' '# <<< dl-research-toolbox bashrc proxy hook <<<'
  echo "Removed bashrc proxy hook from: $BASHRC_FILE"
}

show_status() {
  echo "Autostart status"
  echo "----------------"
  if [ -f "$(system_service_file)" ]; then echo "system service file: $(system_service_file)"; else echo "system service file: missing"; fi
  if systemd_system_available; then
    systemctl is-enabled "$(system_service_name)" 2>/dev/null || true
    systemctl --no-pager --full status "$(system_service_name)" 2>/dev/null | sed -n '1,10p' || true
  else
    echo "systemd system manager: unavailable"
  fi

  if [ -f "$(user_service_file)" ]; then echo "user service file: $(user_service_file)"; else echo "user service file: missing"; fi
  if systemd_user_available; then
    systemctl --user is-enabled "$(user_service_name)" 2>/dev/null || true
    systemctl --user --no-pager --full status "$(user_service_name)" 2>/dev/null | sed -n '1,10p' || true
  else
    echo "systemd user manager: unavailable"
  fi

  if [ -f "$PROFILE_FILE" ] && grep -Fq 'dl-research-toolbox mihomo autostart' "$PROFILE_FILE"; then
    echo "profile hook: installed in $PROFILE_FILE"
  else
    echo "profile hook: missing from $PROFILE_FILE"
  fi
  if [ -n "$PROFILED_FILE" ] && [ -f "$PROFILED_FILE" ] && grep -Fq 'dl-research-toolbox shell proxy hook' "$PROFILED_FILE"; then
    echo "shell proxy env hook: installed in $PROFILED_FILE"
  elif [ -n "$PROFILED_FILE" ]; then
    echo "shell proxy env hook: missing from $PROFILED_FILE"
  else
    echo "shell proxy env hook: unavailable for this user"
  fi
  if [ -f "$BASHRC_FILE" ] && grep -Fq 'dl-research-toolbox bashrc proxy hook' "$BASHRC_FILE"; then
    echo "bashrc proxy hook: installed in $BASHRC_FILE"
  else
    echo "bashrc proxy hook: missing from $BASHRC_FILE"
  fi
  bash "$SCRIPT_DIR/mihomo-status.sh" --test-proxy --no-log || true
}

case "$ACTION" in
  install)
    case "$MODE" in
      system) install_system_service; install_shell_env_hook ;;
      user) install_user_service; install_shell_env_hook ;;
      profile) install_profile_hook; install_shell_env_hook ;;
      auto)
        if can_install_system_service; then
          install_system_service
        elif systemd_user_available; then
          install_user_service
        else
          if systemd_system_available; then
            echo "systemd system manager is available, but root/sudo access is missing; falling back to profile autostart."
          else
            echo "systemd unavailable; falling back to profile autostart."
          fi
          install_profile_hook
        fi
        install_shell_env_hook
        ;;
    esac
    ;;
  uninstall)
    uninstall_system_service
    uninstall_user_service
    uninstall_profile_hook
    uninstall_shell_env_hook
    ;;
  status)
    show_status
    ;;
esac
