#!/usr/bin/env bash
set -Eeuo pipefail

MIHOMO_BIN="${MIHOMO_BIN:-$(command -v mihomo || true)}"
MIHOMO_CONFIG_DIR="${MIHOMO_CONFIG_DIR:-$HOME/.config/mihomo}"
MIHOMO_STATE_DIR="${MIHOMO_STATE_DIR:-$HOME/.local/state/mihomo}"
MIHOMO_LOG="${MIHOMO_LOG:-$MIHOMO_STATE_DIR/mihomo.log}"
MIHOMO_PID_FILE="${MIHOMO_PID_FILE:-$MIHOMO_STATE_DIR/mihomo.pid}"

if [ -z "$MIHOMO_BIN" ] && [ -x "$HOME/.local/bin/mihomo" ]; then
  MIHOMO_BIN="$HOME/.local/bin/mihomo"
fi

if [ -z "$MIHOMO_BIN" ]; then
  echo "mihomo not found. Run: bash scripts/mihomo-install.sh" >&2
  exit 1
fi

if [ ! -x "$MIHOMO_BIN" ]; then
  echo "mihomo is not executable: $MIHOMO_BIN" >&2
  exit 1
fi

mkdir -p "$MIHOMO_CONFIG_DIR" "$MIHOMO_STATE_DIR"

if [ ! -f "$MIHOMO_CONFIG_DIR/config.yaml" ]; then
  echo "Missing config: $MIHOMO_CONFIG_DIR/config.yaml" >&2
  echo "Create it from network/mihomo/config.yaml.example and add your own nodes." >&2
  exit 1
fi

if [ -f "$MIHOMO_PID_FILE" ]; then
  OLD_PID="$(cat "$MIHOMO_PID_FILE" 2>/dev/null || true)"
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" >/dev/null 2>&1; then
    echo "mihomo already running with PID $OLD_PID"
    exit 0
  fi
fi

nohup "$MIHOMO_BIN" -d "$MIHOMO_CONFIG_DIR" > "$MIHOMO_LOG" 2>&1 &
PID="$!"
echo "$PID" > "$MIHOMO_PID_FILE"

sleep 1
if kill -0 "$PID" >/dev/null 2>&1; then
  echo "mihomo started with PID $PID"
  echo "log: $MIHOMO_LOG"
else
  echo "mihomo failed to start. Recent log:" >&2
  tail -n 40 "$MIHOMO_LOG" >&2 || true
  exit 1
fi
