#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

MIHOMO_CONFIG_DIR="${MIHOMO_CONFIG_DIR:-$HOME/.config/mihomo}"
MIHOMO_STATE_DIR="${MIHOMO_STATE_DIR:-$HOME/.local/state/mihomo}"
MIHOMO_MIXED_PORT="${MIHOMO_MIXED_PORT:-7890}"
MIHOMO_EXTERNAL_CONTROLLER="${MIHOMO_EXTERNAL_CONTROLLER:-127.0.0.1:9090}"
MIHOMO_DNS_LISTEN="${MIHOMO_DNS_LISTEN:-127.0.0.1:1053}"
MIHOMO_TEST_URLS="${MIHOMO_TEST_URLS:-https://github.com https://huggingface.co https://pypi.org}"
CONFIG_FILE="$MIHOMO_CONFIG_DIR/config.yaml"
BACKUP_DIR="$MIHOMO_CONFIG_DIR/backups"
URL="${MIHOMO_SUBSCRIPTION_URL:-}"
SOURCE_FILE="${MIHOMO_SUBSCRIPTION_FILE:-}"
START=1
CHECK=1
REPLACE_RUNNING=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/mihomo-import-subscription.sh [--file PATH | --url URL] [--no-start] [--no-check] [--replace-running]

Import a local Clash/Mihomo YAML file into ~/.config/mihomo/config.yaml,
validate the config with mihomo, start mihomo, then check listeners and proxy
connectivity. Local YAML import is the recommended cold-start path because a
subscription URL may be unreachable before the proxy is already running.

Recommended usage:
  bash scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml

Options:
  --file PATH         Local Clash/Mihomo YAML file to import. Recommended.
  --url URL           Subscription URL. Use only when direct network access already works.
  --config-file PATH  Alias for --file.
  --no-start          Only import and validate config; do not start mihomo.
  --no-check          Skip listener and proxy egress checks.
  --replace-running   Stop any existing mihomo process before starting this config.

Environment:
  MIHOMO_CONFIG_DIR              default: ~/.config/mihomo
  MIHOMO_MIXED_PORT              default: 7890, added only when subscription omits mixed-port
  MIHOMO_EXTERNAL_CONTROLLER     default: 127.0.0.1:9090, added only when omitted
  MIHOMO_DNS_LISTEN              default: 127.0.0.1:1053, added only when omitted
  MIHOMO_TEST_URLS               URLs used by status --test-proxy

Notes:
  This script expects Clash/Mihomo YAML. If your provider gives a raw
  ss/vmess/vless/trojan node-list subscription, convert it to YAML locally on a
  machine that already has network access. This script does not send your
  subscription URL to third-party converters.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      URL="${2:-}"
      shift 2
      ;;
    --file|--config-file|--yaml)
      SOURCE_FILE="${2:-}"
      shift 2
      ;;
    --no-start)
      START=0
      shift
      ;;
    --no-check)
      CHECK=0
      shift
      ;;
    --replace-running)
      REPLACE_RUNNING=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -z "$SOURCE_FILE" ] && [ -f "$1" ]; then
        SOURCE_FILE="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        echo "Pass a local YAML path with --file, or use --url explicitly when network already works." >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

if [ -n "$URL" ] && [ -n "$SOURCE_FILE" ]; then
  echo "Use either --url or --file, not both." >&2
  exit 2
fi

if [ -z "$URL" ] && [ -z "$SOURCE_FILE" ]; then
  printf 'Local Clash/Mihomo YAML file path: '
  IFS= read -r SOURCE_FILE
fi

if [ -z "$URL" ] && [ -z "$SOURCE_FILE" ]; then
  echo "YAML file path is empty. Use --file /path/to/mihomo.yaml, or --url only after direct network access works." >&2
  exit 2
fi

if [ -n "$SOURCE_FILE" ] && [ ! -f "$SOURCE_FILE" ]; then
  echo "Mihomo YAML file not found: $SOURCE_FILE" >&2
  exit 2
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

looks_like_clash_yaml() {
  grep -Eq '^(proxies|proxy-providers|proxy-groups|rules|mixed-port|port|socks-port):' "$1"
}

looks_like_raw_nodes() {
  grep -Eiq '^[[:space:]]*(ss|ssr|vmess|vless|trojan|hysteria|hysteria2|tuic)://' "$1"
}

top_level_has_key() {
  local key="$1"
  local file="$2"
  grep -Eq "^${key}:" "$file"
}

append_header_if_missing() {
  local key="$1"
  local line="$2"
  local source_file="$3"
  local header_file="$4"
  if ! top_level_has_key "$key" "$source_file"; then
    printf '%s\n' "$line" >> "$header_file"
  fi
}

extract_proxy_names() {
  local file="$1"
  awk '
    /^proxies:[[:space:]]*$/ { in_proxies = 1; next }
    /^[^[:space:]-][^:]*:/ { in_proxies = 0 }
    in_proxies && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
      gsub(/^['"'"']|['"'"']$/, "", line)
      print line
    }
    in_proxies && /^[[:space:]]*-[[:space:]]*\{/ && /name:[[:space:]]*/ {
      line = $0
      sub(/^.*name:[[:space:]]*/, "", line)
      sub(/,[[:space:]]*.*$/, "", line)
      gsub(/^['"'"']|['"'"']$/, "", line)
      print line
    }
  ' "$file" | sed '/^[[:space:]]*$/d' | head -n 200
}

extract_provider_names() {
  local file="$1"
  awk '
    /^proxy-providers:[[:space:]]*$/ { in_providers = 1; next }
    /^[^[:space:]-][^:]*:/ { in_providers = 0 }
    in_providers && /^[[:space:]]{2}[^[:space:]#][^:]*:[[:space:]]*$/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/:[[:space:]]*$/, "", line)
      print line
    }
  ' "$file" | sed '/^[[:space:]]*$/d' | head -n 50
}

write_proxy_group_if_missing() {
  local source_file="$1"
  local target_file="$2"
  if top_level_has_key proxy-groups "$source_file"; then
    return 0
  fi

  {
    printf '\nproxy-groups:\n'
    printf '  - name: PROXY\n'
    printf '    type: select\n'
    printf '    proxies:\n'
    local wrote=0
    local name escaped
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      escaped="${name//\"/\\\"}"
      printf '      - "%s"\n' "$escaped"
      wrote=1
    done < <(extract_proxy_names "$source_file")
    printf '      - DIRECT\n'
    if top_level_has_key proxy-providers "$source_file"; then
      printf '    use:\n'
      while IFS= read -r name; do
        [ -z "$name" ] && continue
        escaped="${name//\"/\\\"}"
        printf '      - "%s"\n' "$escaped"
        wrote=1
      done < <(extract_provider_names "$source_file")
    fi
    if [ "$wrote" -eq 0 ]; then
      printf '\n# No proxy names were detected automatically; edit PROXY group if needed.\n'
    fi
  } >> "$target_file"
}

write_rules_if_missing() {
  local source_file="$1"
  local target_file="$2"
  if top_level_has_key rules "$source_file"; then
    return 0
  fi

  cat >> "$target_file" <<'RULES'

rules:
  - DOMAIN-SUFFIX,github.com,PROXY
  - DOMAIN-SUFFIX,githubusercontent.com,PROXY
  - DOMAIN-SUFFIX,huggingface.co,PROXY
  - DOMAIN-SUFFIX,hf.co,PROXY
  - DOMAIN-SUFFIX,pypi.org,PROXY
  - DOMAIN-SUFFIX,pythonhosted.org,PROXY
  - DOMAIN-SUFFIX,cn,DIRECT
  - MATCH,PROXY
RULES
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

kill_existing_mihomo() {
  local pids
  pids="$(pgrep -f '(^|/)mihomo( |$)' || true)"
  if [ -z "$pids" ]; then
    return 0
  fi
  echo "Stopping existing mihomo process(es): $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 2
  pids="$(pgrep -f '(^|/)mihomo( |$)' || true)"
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

ensure_mihomo() {
  MIHOMO_BIN="${MIHOMO_BIN:-$(command -v mihomo || true)}"
  if [ -z "$MIHOMO_BIN" ] && [ -x "$HOME/.local/bin/mihomo" ]; then
    MIHOMO_BIN="$HOME/.local/bin/mihomo"
  fi
  if [ -n "$MIHOMO_BIN" ] && [ -x "$MIHOMO_BIN" ]; then
    return 0
  fi

  echo "mihomo not found; installing first..."
  bash "$SCRIPT_DIR/mihomo-install.sh"
  MIHOMO_BIN="${MIHOMO_BIN:-$(command -v mihomo || true)}"
  if [ -z "$MIHOMO_BIN" ] && [ -x "$HOME/.local/bin/mihomo" ]; then
    MIHOMO_BIN="$HOME/.local/bin/mihomo"
  fi
  if [ -z "$MIHOMO_BIN" ] || [ ! -x "$MIHOMO_BIN" ]; then
    echo "mihomo install finished, but binary is not on PATH or ~/.local/bin/mihomo." >&2
    exit 1
  fi
}

if [ -n "$URL" ]; then
  require_cmd curl
fi
require_cmd awk
require_cmd sed
ensure_mihomo

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
RAW_FILE="$TMP_DIR/subscription.raw"
CLEAN_FILE="$TMP_DIR/subscription.clean.yaml"
DECODED_FILE="$TMP_DIR/subscription.decoded"
HEADER_FILE="$TMP_DIR/header.yaml"
FINAL_FILE="$TMP_DIR/config.yaml"
: > "$HEADER_FILE"

mkdir -p "$MIHOMO_CONFIG_DIR" "$BACKUP_DIR" "$MIHOMO_STATE_DIR"

if [ -f "$CONFIG_FILE" ]; then
  BACKUP_FILE="$BACKUP_DIR/config.$(date +%Y%m%dT%H%M%S).yaml"
else
  BACKUP_FILE=""
fi

if [ -n "$SOURCE_FILE" ]; then
  echo "Reading local mihomo YAML file: $SOURCE_FILE"
  cp "$SOURCE_FILE" "$RAW_FILE"
else
  echo "Downloading subscription URL. This requires direct network access before proxy startup; prefer --file for cold-start machines."
  curl -fsSL --retry 2 --connect-timeout 15 --max-time 90 \
    -A 'ClashforWindows/0.20.39' \
    "$URL" -o "$RAW_FILE"
fi

tr -d '\r' < "$RAW_FILE" > "$CLEAN_FILE"

if [ ! -s "$CLEAN_FILE" ]; then
  echo "Mihomo import source is empty." >&2
  exit 1
fi

if head -c 256 "$CLEAN_FILE" | grep -Eiq '<html|<!doctype'; then
  echo "Import source looks like HTML, not a mihomo config. Check the URL, file, or authentication." >&2
  exit 1
fi

if ! looks_like_clash_yaml "$CLEAN_FILE"; then
  COMPACT_FILE="$TMP_DIR/subscription.compact"
  tr -d '\r\n\t ' < "$CLEAN_FILE" > "$COMPACT_FILE"
  if [ -s "$COMPACT_FILE" ] && base64 -d "$COMPACT_FILE" > "$DECODED_FILE" 2>/dev/null; then
    tr -d '\r' < "$DECODED_FILE" > "$CLEAN_FILE"
  fi
fi

if ! looks_like_clash_yaml "$CLEAN_FILE"; then
  if looks_like_raw_nodes "$CLEAN_FILE"; then
    echo "The subscription is a raw node-list, not Clash/Mihomo YAML." >&2
    echo "Convert it locally to Clash/Mihomo YAML first, then import with --file." >&2
  else
    echo "The subscription is not recognized as Clash/Mihomo YAML." >&2
  fi
  exit 1
fi

append_header_if_missing mixed-port "mixed-port: $MIHOMO_MIXED_PORT" "$CLEAN_FILE" "$HEADER_FILE"
append_header_if_missing allow-lan "allow-lan: false" "$CLEAN_FILE" "$HEADER_FILE"
append_header_if_missing mode "mode: rule" "$CLEAN_FILE" "$HEADER_FILE"
append_header_if_missing log-level "log-level: info" "$CLEAN_FILE" "$HEADER_FILE"
append_header_if_missing ipv6 "ipv6: false" "$CLEAN_FILE" "$HEADER_FILE"
append_header_if_missing external-controller "external-controller: $MIHOMO_EXTERNAL_CONTROLLER" "$CLEAN_FILE" "$HEADER_FILE"
append_header_if_missing secret 'secret: ""' "$CLEAN_FILE" "$HEADER_FILE"

if ! top_level_has_key dns "$CLEAN_FILE"; then
  cat >> "$HEADER_FILE" <<DNS

dns:
  enable: true
  listen: $MIHOMO_DNS_LISTEN
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
    - 1.1.1.1
    - 8.8.8.8
DNS
fi

if [ -s "$HEADER_FILE" ]; then
  cat "$HEADER_FILE" "$CLEAN_FILE" > "$FINAL_FILE"
else
  cp "$CLEAN_FILE" "$FINAL_FILE"
fi
write_proxy_group_if_missing "$CLEAN_FILE" "$FINAL_FILE"
write_rules_if_missing "$CLEAN_FILE" "$FINAL_FILE"

if [ -n "$BACKUP_FILE" ]; then
  cp "$CONFIG_FILE" "$BACKUP_FILE"
  chmod 600 "$BACKUP_FILE"
  echo "Backed up existing config: $BACKUP_FILE"
fi

cp "$FINAL_FILE" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
echo "Imported config: $CONFIG_FILE"

if ! "$MIHOMO_BIN" -t -d "$MIHOMO_CONFIG_DIR" >/tmp/mihomo-config-test.log 2>&1; then
  echo "mihomo config test failed:" >&2
  sed -n '1,120p' /tmp/mihomo-config-test.log >&2 || true
  if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo "Restored previous config from backup." >&2
  fi
  exit 1
fi

echo "mihomo config test passed."

if [ "$START" -eq 1 ]; then
  if [ "$REPLACE_RUNNING" -eq 1 ]; then
    kill_existing_mihomo
  fi

  bash "$SCRIPT_DIR/mihomo-stop.sh" >/dev/null 2>&1 || true

  IMPORTED_PORT="$(awk -F: '/^[[:space:]]*mixed-port:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$CONFIG_FILE")"
  if [ -n "$IMPORTED_PORT" ] && tcp_listening "$IMPORTED_PORT" && [ "$REPLACE_RUNNING" -eq 0 ]; then
    echo "mixed-port tcp/$IMPORTED_PORT is already listening before start." >&2
    echo "If this is an old mihomo process, rerun with --replace-running." >&2
    exit 1
  fi

  bash "$SCRIPT_DIR/mihomo-start.sh"
fi

if [ "$CHECK" -eq 1 ]; then
  export MIHOMO_CONFIG_DIR MIHOMO_STATE_DIR MIHOMO_TEST_URLS
  bash "$SCRIPT_DIR/mihomo-status.sh" --strict --test-proxy
fi

echo "Mihomo config import complete."
