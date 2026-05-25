#!/usr/bin/env bash
set -Eeuo pipefail

STRICT=0
TEST_PROXY=0
SHOW_LOG=1

usage() {
  cat <<'USAGE'
Usage: bash scripts/mihomo-status.sh [--strict] [--test-proxy] [--no-log]

Checks mihomo process state, configured listener ports, controller health, and
optionally proxy egress through mixed-port.

Options:
  --strict      Exit non-zero when required checks fail.
  --test-proxy  Test HTTPS egress through http://127.0.0.1:<mixed-port>.
  --no-log      Do not print recent log lines.

Environment:
  MIHOMO_CONFIG_DIR          default: ~/.config/mihomo
  MIHOMO_STATE_DIR           default: ~/.local/state/mihomo
  MIHOMO_TEST_URLS           space-separated URLs for --test-proxy
  MIHOMO_TEST_RETRIES        default: 3
  MIHOMO_TEST_RETRY_SLEEP    default: 2
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --test-proxy) TEST_PROXY=1; shift ;;
    --no-log) SHOW_LOG=0; shift ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

MIHOMO_BIN="${MIHOMO_BIN:-$(command -v mihomo || true)}"
if [ -z "$MIHOMO_BIN" ] && [ -x "$HOME/.local/bin/mihomo" ]; then
  MIHOMO_BIN="$HOME/.local/bin/mihomo"
fi
MIHOMO_CONFIG_DIR="${MIHOMO_CONFIG_DIR:-$HOME/.config/mihomo}"
MIHOMO_STATE_DIR="${MIHOMO_STATE_DIR:-$HOME/.local/state/mihomo}"
MIHOMO_LOG="${MIHOMO_LOG:-$MIHOMO_STATE_DIR/mihomo.log}"
MIHOMO_PID_FILE="${MIHOMO_PID_FILE:-$MIHOMO_STATE_DIR/mihomo.pid}"
MIHOMO_TEST_URLS="${MIHOMO_TEST_URLS:-https://github.com https://huggingface.co https://pypi.org}"
MIHOMO_TEST_RETRIES="${MIHOMO_TEST_RETRIES:-3}"
MIHOMO_TEST_RETRY_SLEEP="${MIHOMO_TEST_RETRY_SLEEP:-2}"
CONFIG_FILE="$MIHOMO_CONFIG_DIR/config.yaml"
FAILURES=0

case "$MIHOMO_TEST_RETRIES" in
  ''|*[!0-9]*) echo "MIHOMO_TEST_RETRIES must be a positive integer." >&2; exit 2 ;;
esac
if [ "$MIHOMO_TEST_RETRIES" -lt 1 ]; then
  MIHOMO_TEST_RETRIES=1
fi
case "$MIHOMO_TEST_RETRY_SLEEP" in
  ''|*[!0-9]*) echo "MIHOMO_TEST_RETRY_SLEEP must be a non-negative integer." >&2; exit 2 ;;
esac

mark_fail() {
  FAILURES=$((FAILURES + 1))
}

read_yaml_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    $0 ~ "^" key ":" {
      value = $0
      sub("^" key ":[[:space:]]*", "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file" | sed -E "s/^[\"']//; s/[\"']$//"
}

read_any_yaml_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":" {
      value = $0
      sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file" | sed -E "s/^[\"']//; s/[\"']$//"
}

tcp_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -ltn 2>/dev/null | awk -v port="$port" '
      $4 ~ ":" port "$" { found = 1 }
      END { exit found ? 0 : 1 }
    '
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -nP >/dev/null 2>&1
  else
    return 2
  fi
}

udp_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -lun 2>/dev/null | awk -v port="$port" '
      $5 ~ ":" port "$" { found = 1 }
      END { exit found ? 0 : 1 }
    '
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iUDP:"$port" -nP >/dev/null 2>&1
  else
    return 2
  fi
}

show_tcp_listener() {
  local label="$1"
  local port="$2"
  if [ -z "$port" ]; then
    return 0
  fi

  local status=0
  tcp_listening "$port" || status=$?
  if [ "$status" -eq 0 ]; then
    echo "[listen] $label tcp/$port is listening"
    if command -v ss >/dev/null 2>&1; then
      ss -H -ltnp "sport = :$port" 2>/dev/null | head -n 3 | sed 's/^/  /' || true
    fi
  elif [ "$status" -eq 2 ]; then
    echo "[listen] $label tcp/$port cannot be checked because ss/lsof is not installed"
  else
    echo "[listen] $label tcp/$port is not listening"
    if [ "$STRICT" -eq 1 ]; then mark_fail; fi
  fi
}

show_udp_listener() {
  local label="$1"
  local port="$2"
  if [ -z "$port" ]; then
    return 0
  fi

  local status=0
  udp_listening "$port" || status=$?
  if [ "$status" -eq 0 ]; then
    echo "[listen] $label udp/$port is listening"
    if command -v ss >/dev/null 2>&1; then
      ss -H -lunp "sport = :$port" 2>/dev/null | head -n 3 | sed 's/^/  /' || true
    fi
  elif [ "$status" -eq 2 ]; then
    echo "[listen] $label udp/$port cannot be checked because ss/lsof is not installed"
  else
    echo "[listen] $label udp/$port is not listening"
    if [ "$STRICT" -eq 1 ] && [ "$label" != "dns" ]; then mark_fail; fi
  fi
}

controller_probe() {
  local controller="$1"
  local secret="$2"
  local host="${controller%:*}"
  local port="${controller##*:}"

  if [ -z "$controller" ] || [ "$controller" = "$port" ]; then
    return 0
  fi

  [ -z "$host" ] && host="127.0.0.1"
  [ "$host" = "0.0.0.0" ] && host="127.0.0.1"

  show_tcp_listener "external-controller" "$port"

  local curl_args=(-fsS --max-time 3)
  if [ -n "$secret" ]; then
    curl_args+=(-H "Authorization: Bearer $secret")
  fi

  if command -v curl >/dev/null 2>&1 && curl "${curl_args[@]}" "http://${host}:${port}/version" >/dev/null 2>&1; then
    echo "[controller] reachable at http://${host}:${port}/version"
  else
    echo "[controller] not reachable at http://${host}:${port}/version"
    if [ "$STRICT" -eq 1 ]; then mark_fail; fi
  fi
}

proxy_probe() {
  local port="$1"
  if [ "$TEST_PROXY" -eq 0 ]; then
    return 0
  fi
  if [ -z "$port" ]; then
    echo "[proxy] mixed-port is missing; cannot test proxy egress"
    if [ "$STRICT" -eq 1 ]; then mark_fail; fi
    return 0
  fi
  local listen_status=0
  tcp_listening "$port" || listen_status=$?
  if [ "$listen_status" -eq 1 ]; then
    echo "[proxy] mixed-port tcp/$port is not listening; skipping egress test"
    if [ "$STRICT" -eq 1 ]; then mark_fail; fi
    return 0
  elif [ "$listen_status" -eq 2 ]; then
    echo "[proxy] listener tools missing; probing 127.0.0.1:$port with curl"
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "[proxy] curl not found; cannot test proxy egress"
    if [ "$STRICT" -eq 1 ]; then mark_fail; fi
    return 0
  fi

  local url attempt err_file err_msg
  for url in $MIHOMO_TEST_URLS; do
    err_file="$(mktemp)"
    for attempt in $(seq 1 "$MIHOMO_TEST_RETRIES"); do
      if curl -fsS -o /dev/null --connect-timeout 6 --max-time 20 -x "http://127.0.0.1:${port}" "$url" 2>"$err_file"; then
        echo "[proxy] ok: $url via 127.0.0.1:$port"
        rm -f "$err_file"
        continue 2
      fi
      err_msg="$(tr '\n' ' ' < "$err_file" | sed 's/[[:space:]]*$//')"
      if [ "$attempt" -lt "$MIHOMO_TEST_RETRIES" ]; then
        echo "[proxy] retry $attempt/$MIHOMO_TEST_RETRIES: $url via 127.0.0.1:$port${err_msg:+ ($err_msg)}"
        sleep "$MIHOMO_TEST_RETRY_SLEEP"
      fi
    done
    if [ -s "$err_file" ]; then
      cat "$err_file" >&2
    fi
    rm -f "$err_file"
    echo "[proxy] fail: $url via 127.0.0.1:$port"
    if [ "$STRICT" -eq 1 ]; then mark_fail; fi
  done
}

echo "mihomo status"
echo "-------------"

if [ -n "$MIHOMO_BIN" ]; then
  echo "binary: $MIHOMO_BIN"
else
  echo "binary: not found"
  if [ "$STRICT" -eq 1 ]; then mark_fail; fi
fi

if [ -f "$MIHOMO_PID_FILE" ]; then
  PID="$(cat "$MIHOMO_PID_FILE" 2>/dev/null || true)"
  if [ -n "$PID" ] && kill -0 "$PID" >/dev/null 2>&1; then
    echo "process: running pid=$PID"
  else
    echo "process: stale pid file"
    if [ "$STRICT" -eq 1 ]; then mark_fail; fi
  fi
else
  echo "process: no pid file"
  if [ "$STRICT" -eq 1 ]; then mark_fail; fi
fi

if [ -f "$CONFIG_FILE" ]; then
  MIXED_PORT="$(read_yaml_value mixed-port "$CONFIG_FILE" || true)"
  HTTP_PORT="$(read_yaml_value port "$CONFIG_FILE" || true)"
  SOCKS_PORT="$(read_yaml_value socks-port "$CONFIG_FILE" || true)"
  REDIR_PORT="$(read_yaml_value redir-port "$CONFIG_FILE" || true)"
  TPROXY_PORT="$(read_yaml_value tproxy-port "$CONFIG_FILE" || true)"
  DNS_LISTEN="$(read_any_yaml_value listen "$CONFIG_FILE" || true)"
  DNS_PORT=""
  [ -n "$DNS_LISTEN" ] && DNS_PORT="${DNS_LISTEN##*:}"
  EXTERNAL_CONTROLLER="$(read_yaml_value external-controller "$CONFIG_FILE" || true)"
  CONTROLLER_SECRET="$(read_yaml_value secret "$CONFIG_FILE" || true)"

  echo "config: $CONFIG_FILE"
  [ -n "$MIXED_PORT" ] && echo "mixed-port: $MIXED_PORT"
  [ -n "$HTTP_PORT" ] && echo "port: $HTTP_PORT"
  [ -n "$SOCKS_PORT" ] && echo "socks-port: $SOCKS_PORT"
  [ -n "$EXTERNAL_CONTROLLER" ] && echo "external-controller: $EXTERNAL_CONTROLLER"

  show_tcp_listener "mixed-port" "$MIXED_PORT"
  show_tcp_listener "http-port" "$HTTP_PORT"
  show_tcp_listener "socks-port" "$SOCKS_PORT"
  show_tcp_listener "redir-port" "$REDIR_PORT"
  show_tcp_listener "tproxy-port" "$TPROXY_PORT"
  show_udp_listener "dns" "$DNS_PORT"
  controller_probe "$EXTERNAL_CONTROLLER" "$CONTROLLER_SECRET"
  proxy_probe "$MIXED_PORT"
else
  echo "config: missing $CONFIG_FILE"
  if [ "$STRICT" -eq 1 ]; then mark_fail; fi
fi

if [ "$SHOW_LOG" -eq 1 ]; then
  if [ -f "$MIHOMO_LOG" ]; then
    echo "log: $MIHOMO_LOG"
    echo "recent log:"
    tail -n 20 "$MIHOMO_LOG"
  else
    echo "log: missing $MIHOMO_LOG"
  fi
fi

if [ "$STRICT" -eq 1 ] && [ "$FAILURES" -gt 0 ]; then
  echo "strict check failed: $FAILURES issue(s)" >&2
  exit 1
fi
