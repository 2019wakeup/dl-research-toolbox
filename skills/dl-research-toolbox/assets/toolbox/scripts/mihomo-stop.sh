#!/usr/bin/env bash
set -Eeuo pipefail

MIHOMO_STATE_DIR="${MIHOMO_STATE_DIR:-$HOME/.local/state/mihomo}"
MIHOMO_PID_FILE="${MIHOMO_PID_FILE:-$MIHOMO_STATE_DIR/mihomo.pid}"

if [ ! -f "$MIHOMO_PID_FILE" ]; then
  echo "No PID file found: $MIHOMO_PID_FILE"
  exit 0
fi

PID="$(cat "$MIHOMO_PID_FILE" 2>/dev/null || true)"
if [ -z "$PID" ]; then
  rm -f "$MIHOMO_PID_FILE"
  echo "Empty PID file removed."
  exit 0
fi

if ! kill -0 "$PID" >/dev/null 2>&1; then
  rm -f "$MIHOMO_PID_FILE"
  echo "mihomo process is not running. PID file removed."
  exit 0
fi

kill "$PID"
for _ in 1 2 3 4 5; do
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    rm -f "$MIHOMO_PID_FILE"
    echo "mihomo stopped."
    exit 0
  fi
  sleep 1
done

kill -9 "$PID"
rm -f "$MIHOMO_PID_FILE"
echo "mihomo force-stopped."
