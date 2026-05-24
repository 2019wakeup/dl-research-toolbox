#!/usr/bin/env bash
set -Eeuo pipefail

MIHOMO_BIN="${MIHOMO_BIN:-$(command -v mihomo || true)}"
MIHOMO_CONFIG_DIR="${MIHOMO_CONFIG_DIR:-$HOME/.config/mihomo}"
MIHOMO_STATE_DIR="${MIHOMO_STATE_DIR:-$HOME/.local/state/mihomo}"
MIHOMO_LOG="${MIHOMO_LOG:-$MIHOMO_STATE_DIR/mihomo.log}"
MIHOMO_PID_FILE="${MIHOMO_PID_FILE:-$MIHOMO_STATE_DIR/mihomo.pid}"
CONFIG_FILE="$MIHOMO_CONFIG_DIR/config.yaml"

read_yaml_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" "
    \$0 ~ \"^[[:space:]]*\" key \":\" {
      value = \$0
      sub(\"^[[:space:]]*\" key \":[[:space:]]*\", \"\", value)
      sub(/[[:space:]]+$/, \"\", value)
      gsub(/\\\"/, \"\", value)
      print value
      exit
    }
  " "$file"
}

echo "mihomo status"
echo "-------------"

if [ -n "$MIHOMO_BIN" ]; then
  echo "binary: $MIHOMO_BIN"
else
  echo "binary: not found"
fi

if [ -f "$MIHOMO_PID_FILE" ]; then
  PID="$(cat "$MIHOMO_PID_FILE" 2>/dev/null || true)"
  if [ -n "$PID" ] && kill -0 "$PID" >/dev/null 2>&1; then
    echo "process: running pid=$PID"
  else
    echo "process: stale pid file"
  fi
else
  echo "process: no pid file"
fi

if [ -f "$CONFIG_FILE" ]; then
  MIXED_PORT="$(read_yaml_value mixed-port "$CONFIG_FILE" || true)"
  EXTERNAL_CONTROLLER="$(read_yaml_value external-controller "$CONFIG_FILE" || true)"
  echo "config: $CONFIG_FILE"
  [ -n "$MIXED_PORT" ] && echo "mixed-port: $MIXED_PORT"
  [ -n "$EXTERNAL_CONTROLLER" ] && echo "external-controller: $EXTERNAL_CONTROLLER"

  if command -v ss >/dev/null 2>&1 && [ -n "$MIXED_PORT" ]; then
    if ss -ltn | awk '{print $4}' | grep -Eq "[:.]${MIXED_PORT}$"; then
      echo "port: mixed-port is listening"
    else
      echo "port: mixed-port is not listening"
    fi
  fi

  if [ -n "$EXTERNAL_CONTROLLER" ] && command -v curl >/dev/null 2>&1; then
    CONTROLLER_HOST="${EXTERNAL_CONTROLLER%:*}"
    CONTROLLER_PORT="${EXTERNAL_CONTROLLER##*:}"
    [ "$CONTROLLER_HOST" = "0.0.0.0" ] && CONTROLLER_HOST="127.0.0.1"
    if curl -fsS --max-time 2 "http://${CONTROLLER_HOST}:${CONTROLLER_PORT}/version" >/dev/null 2>&1; then
      echo "controller: reachable"
    else
      echo "controller: not reachable"
    fi
  fi
else
  echo "config: missing $CONFIG_FILE"
fi

if [ -f "$MIHOMO_LOG" ]; then
  echo "log: $MIHOMO_LOG"
  echo "recent log:"
  tail -n 20 "$MIHOMO_LOG"
else
  echo "log: missing $MIHOMO_LOG"
fi
