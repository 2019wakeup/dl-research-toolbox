#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dl-research-toolbox"
CONFIG_FILE="$CONFIG_DIR/web-tunnel.env"
TARGET="${TOOLBOX_SSH_TARGET:-}"
SSH_PORT="${TOOLBOX_SSH_PORT:-}"
REMOTE_DIR="${TOOLBOX_REMOTE_DIR:-~/dl-research-toolbox}"
LOCAL_PORT="${TOOLBOX_WEB_LOCAL_PORT:-8765}"
REMOTE_PORT="${TOOLBOX_WEB_REMOTE_PORT:-8765}"
SAVE_PROFILE=0
PRINT_ONLY=0
EXTRA_SSH_ARGS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/web-tunnel.sh [options] [user@server]

Local-side helper for the toolbox Web UI. It opens an SSH tunnel and starts the
remote Web UI in one command. Save the target once, then run without arguments.

Simplest first run from your local machine:
  bash scripts/web-tunnel.sh

The script will ask for the SSH target, save it, then start the remote Web UI.

Non-interactive first run:
  bash scripts/web-tunnel.sh --target root@example.com --ssh-port 22 --remote-dir '~/dl-research-toolbox' --save-profile

Next runs:
  bash scripts/web-tunnel.sh

Options:
  --target TARGET      SSH target, such as root@example.com or an SSH config alias.
  --ssh-port PORT      SSH port for the target.
  -p PORT              Alias for --ssh-port.
  --remote-dir DIR     Remote toolbox directory. Default: ~/dl-research-toolbox.
  --local-port PORT    Local browser port. Default: 8765.
  --remote-port PORT   Remote Web UI port. Default: 8765.
  --save-profile       Save target/ports to ~/.config/dl-research-toolbox/web-tunnel.env.
  --profile PATH       Use another profile path.
  --ssh-arg ARG        Extra ssh argument. May be repeated.
  --print              Print the ssh command instead of running it.
  -h, --help           Show this help.
USAGE
}

require_arg() {
  local opt="$1"
  local value="${2-}"
  if [ -z "$value" ]; then
    echo "Missing value for $opt" >&2
    usage >&2
    exit 2
  fi
}

validate_port() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "$name is required." >&2
    exit 2
  fi
  case "$value" in
    *[!0-9]*)
      echo "$name must be a numeric TCP port: $value" >&2
      exit 2
      ;;
  esac
  if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    echo "$name must be between 1 and 65535: $value" >&2
    exit 2
  fi
}

validate_optional_port() {
  local name="$1"
  local value="$2"
  [ -z "$value" ] || validate_port "$name" "$value"
}

load_profile() {
  [ -f "$CONFIG_FILE" ] || return 0
  local key value
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    case "$key" in \#*) continue ;; esac
    case "$key" in
      TOOLBOX_SSH_TARGET) [ -z "$TARGET" ] && TARGET="$value" ;;
      TOOLBOX_SSH_PORT) [ -z "$SSH_PORT" ] && SSH_PORT="$value" ;;
      TOOLBOX_REMOTE_DIR) [ "$REMOTE_DIR" = "~/dl-research-toolbox" ] && REMOTE_DIR="$value" ;;
      TOOLBOX_WEB_LOCAL_PORT) [ "$LOCAL_PORT" = "8765" ] && LOCAL_PORT="$value" ;;
      TOOLBOX_WEB_REMOTE_PORT) [ "$REMOTE_PORT" = "8765" ] && REMOTE_PORT="$value" ;;
    esac
  done < "$CONFIG_FILE"
}

save_profile() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  {
    printf 'TOOLBOX_SSH_TARGET=%s\n' "$TARGET"
    printf 'TOOLBOX_SSH_PORT=%s\n' "$SSH_PORT"
    printf 'TOOLBOX_REMOTE_DIR=%s\n' "$REMOTE_DIR"
    printf 'TOOLBOX_WEB_LOCAL_PORT=%s\n' "$LOCAL_PORT"
    printf 'TOOLBOX_WEB_REMOTE_PORT=%s\n' "$REMOTE_PORT"
  } > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "Saved Web tunnel profile: $CONFIG_FILE"
}

prompt_profile() {
  [ -z "$TARGET" ] || return 0
  [ -t 0 ] || return 1

  echo "No Web tunnel profile found. Enter the remote SSH details once; they will be saved locally."
  read -r -p "SSH target, such as user@server or an SSH config alias: " TARGET
  read -r -p "SSH port [22]: " SSH_PORT_INPUT
  read -r -p "Remote toolbox directory [$REMOTE_DIR]: " REMOTE_DIR_INPUT
  read -r -p "Local browser port [$LOCAL_PORT]: " LOCAL_PORT_INPUT
  read -r -p "Remote Web UI port [$REMOTE_PORT]: " REMOTE_PORT_INPUT

  SSH_PORT="${SSH_PORT_INPUT:-22}"
  REMOTE_DIR="${REMOTE_DIR_INPUT:-$REMOTE_DIR}"
  LOCAL_PORT="${LOCAL_PORT_INPUT:-$LOCAL_PORT}"
  REMOTE_PORT="${REMOTE_PORT_INPUT:-$REMOTE_PORT}"
  SAVE_PROFILE=1
}

single_quote() {
  local value=${1//\'/\'\\\'\'}
  printf "'%s'" "$value"
}

quote_remote_path() {
  local rest
  case "$1" in
    '~') printf '~' ;;
    '~/'*)
      rest="${1#\~/}"
      if [ -z "$rest" ]; then
        printf '~'
      else
        printf "~/%s" "$(single_quote "$rest")"
      fi
      ;;
    *) single_quote "$1" ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) require_arg "$1" "${2-}"; TARGET="$2"; shift 2 ;;
    --ssh-port|-p) require_arg "$1" "${2-}"; SSH_PORT="$2"; shift 2 ;;
    --remote-dir) require_arg "$1" "${2-}"; REMOTE_DIR="$2"; shift 2 ;;
    --local-port) require_arg "$1" "${2-}"; LOCAL_PORT="$2"; shift 2 ;;
    --remote-port) require_arg "$1" "${2-}"; REMOTE_PORT="$2"; shift 2 ;;
    --save-profile) SAVE_PROFILE=1; shift ;;
    --profile) require_arg "$1" "${2-}"; CONFIG_FILE="$2"; shift 2 ;;
    --ssh-arg) require_arg "$1" "${2-}"; EXTRA_SSH_ARGS+=("$2"); shift 2 ;;
    --print) PRINT_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

load_profile

if ! prompt_profile; then
  :
fi

if [ -z "$TARGET" ]; then
  echo "Missing SSH target." >&2
  echo "Run once interactively with: bash scripts/web-tunnel.sh" >&2
  echo "Or run non-interactively with: bash scripts/web-tunnel.sh --target user@server --ssh-port PORT --save-profile" >&2
  echo "After that, run: bash scripts/web-tunnel.sh" >&2
  exit 2
fi

validate_optional_port "SSH port" "$SSH_PORT"
validate_port "Local browser port" "$LOCAL_PORT"
validate_port "Remote Web UI port" "$REMOTE_PORT"

if [ "$SAVE_PROFILE" -eq 1 ]; then
  save_profile
fi

remote_dir_arg="$(quote_remote_path "$REMOTE_DIR")"
remote_cmd="cd $remote_dir_arg && exec bash scripts/web-ui.sh --host 127.0.0.1 --port $REMOTE_PORT"
ssh_cmd=(ssh -L "${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}")
if [ -n "$SSH_PORT" ]; then
  ssh_cmd+=(-p "$SSH_PORT")
fi
if [ "${#EXTRA_SSH_ARGS[@]}" -gt 0 ]; then
  ssh_cmd+=("${EXTRA_SSH_ARGS[@]}")
fi
ssh_cmd+=("$TARGET" "$remote_cmd")

if [ "$PRINT_ONLY" -eq 1 ]; then
  printf '%q ' "${ssh_cmd[@]}"
  printf '\n'
  exit 0
fi

echo "Opening SSH tunnel: 127.0.0.1:$LOCAL_PORT -> $TARGET:127.0.0.1:$REMOTE_PORT"
echo "Remote command: $remote_cmd"
echo "The remote Web UI will print the tokenized local URL below."
exec "${ssh_cmd[@]}"
