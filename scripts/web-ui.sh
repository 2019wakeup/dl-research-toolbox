#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST="${TOOLBOX_WEB_HOST:-127.0.0.1}"
PORT="${TOOLBOX_WEB_PORT:-8765}"
TOKEN="${TOOLBOX_WEB_TOKEN:-}"
TOKEN_MODE="token"
ARGS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/web-ui.sh [options]

Start a local-only web control panel for monitoring and controlling toolbox
services. Access it with SSH port forwarding; no HTTP tunnel is required.

Server:
  cd ~/dl-research-toolbox
  bash scripts/web-ui.sh --port 8765

Local machine:
  ssh -N -L 8765:127.0.0.1:8765 user@server

Options:
  --host HOST      Bind host. Default: 127.0.0.1.
  --port PORT      Bind port. Default: 8765.
  --token TOKEN    Fixed access token. Default: random token printed at startup.
  --no-token       Disable token check. Only use with localhost binding.
  -h, --help       Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --no-token) TOKEN_MODE="none"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the web UI." >&2
  exit 1
fi

ARGS+=(--host "$HOST" --port "$PORT")
if [ "$TOKEN_MODE" = "none" ]; then
  ARGS+=(--no-token)
elif [ -n "$TOKEN" ]; then
  ARGS+=(--token "$TOKEN")
fi

exec python3 "$SCRIPT_DIR/toolbox-web.py" "${ARGS[@]}"
