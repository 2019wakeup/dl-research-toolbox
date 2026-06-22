#!/usr/bin/env bash
set -Eeuo pipefail

MIHOMO_CONFIG_DIR="${MIHOMO_CONFIG_DIR:-$HOME/.config/mihomo}"
CONFIG_FILE="${MIHOMO_CONFIG_FILE:-$MIHOMO_CONFIG_DIR/config.yaml}"
SELECT_URL="${MIHOMO_SELECT_URL:-https://www.gstatic.com/generate_204}"
DELAY_TIMEOUT="${MIHOMO_SELECT_TIMEOUT:-5000}"
LIMIT="${MIHOMO_SELECT_LIMIT:-120}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/mihomo-select-best.sh [options]

Probe mihomo leaf proxies through the local controller and set selector groups to
an available low-latency proxy. Output intentionally uses indexes instead of real
node names, so logs can be shared without leaking subscription contents.

Options:
  --url URL          Delay-test URL. Default: https://www.gstatic.com/generate_204
  --timeout MS      Per-proxy delay timeout in milliseconds. Default: 5000.
  --limit N         Maximum leaf proxies to probe. Default: 120.
  --dry-run         Probe but do not update selector groups.
  -h, --help        Show this help.

Environment:
  MIHOMO_CONFIG_DIR      default: ~/.config/mihomo
  MIHOMO_CONFIG_FILE     default: $MIHOMO_CONFIG_DIR/config.yaml
  MIHOMO_SELECT_URL      delay-test URL
  MIHOMO_SELECT_TIMEOUT  per-proxy timeout in milliseconds
  MIHOMO_SELECT_LIMIT    maximum leaf proxies to probe
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) SELECT_URL="${2:-}"; shift 2 ;;
    --timeout) DELAY_TIMEOUT="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$DELAY_TIMEOUT" in ''|*[!0-9]*) echo "--timeout must be a positive integer." >&2; exit 2 ;; esac
case "$LIMIT" in ''|*[!0-9]*) echo "--limit must be a positive integer." >&2; exit 2 ;; esac
[ "$DELAY_TIMEOUT" -gt 0 ] || DELAY_TIMEOUT=5000
[ "$LIMIT" -gt 0 ] || LIMIT=120

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

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing mihomo config: $CONFIG_FILE" >&2
  exit 1
fi

CONTROLLER="$(read_yaml_value external-controller "$CONFIG_FILE" || true)"
SECRET="$(read_yaml_value secret "$CONFIG_FILE" || true)"
if [ -z "$CONTROLLER" ]; then
  CONTROLLER="127.0.0.1:9090"
fi
case "$CONTROLLER" in
  http://*|https://*) CONTROLLER_URL="$CONTROLLER" ;;
  *) CONTROLLER_URL="http://$CONTROLLER" ;;
esac
CONTROLLER_URL="${CONTROLLER_URL/0.0.0.0/127.0.0.1}"
CONTROLLER_URL="${CONTROLLER_URL%/}"

MIHOMO_CONTROLLER_URL="$CONTROLLER_URL" \
MIHOMO_CONTROLLER_SECRET="$SECRET" \
MIHOMO_SELECT_URL="$SELECT_URL" \
MIHOMO_SELECT_TIMEOUT="$DELAY_TIMEOUT" \
MIHOMO_SELECT_LIMIT="$LIMIT" \
MIHOMO_SELECT_DRY_RUN="$DRY_RUN" \
python3 - <<'PY_SELECT'
import json
import os
from functools import partial
import urllib.error
import urllib.parse
import urllib.request

print = partial(print, flush=True)

base = os.environ["MIHOMO_CONTROLLER_URL"].rstrip("/")
secret = os.environ.get("MIHOMO_CONTROLLER_SECRET", "")
select_url = os.environ["MIHOMO_SELECT_URL"]
timeout_ms = int(os.environ["MIHOMO_SELECT_TIMEOUT"])
limit = int(os.environ["MIHOMO_SELECT_LIMIT"])
dry_run = os.environ.get("MIHOMO_SELECT_DRY_RUN") == "1"

headers = {}
if secret:
    headers["Authorization"] = f"Bearer {secret}"


def request(path, method="GET", body=None, timeout=8):
    data = None
    hdrs = dict(headers)
    if body is not None:
        data = json.dumps(body).encode()
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, method=method, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    if not raw:
        return None
    return json.loads(raw.decode())

try:
    data = request("/proxies")
except Exception as exc:
    print(f"controller_error: {type(exc).__name__}: {exc}")
    raise SystemExit(1)

proxies = data.get("proxies", {})
groups = []
leaf = []
for name, obj in proxies.items():
    if "all" in obj:
        groups.append((name, obj.get("type"), obj.get("all") or []))
    elif obj.get("type") not in ("Direct", "Reject"):
        leaf.append(name)

print(f"selector_scan: groups={len(groups)} leaf_proxies={len(leaf)} probe_limit={min(limit, len(leaf))}")
results = []
for idx, name in enumerate(leaf[:limit], 1):
    query = urllib.parse.urlencode({"timeout": str(timeout_ms), "url": select_url})
    path = "/proxies/" + urllib.parse.quote(name, safe="") + "/delay?" + query
    try:
        obj = request(path, timeout=max(2, timeout_ms / 1000 + 2)) or {}
        delay = obj.get("delay")
        if isinstance(delay, int) and delay > 0:
            results.append((delay, idx, name))
            print(f"selector_scan: alive_index={idx} delay_ms={delay}")
    except Exception:
        pass

print(f"selector_scan: alive={len(results)}")
if not results:
    raise SystemExit(1)

results.sort()
best_delay, best_idx, best_name = results[0]
print(f"selector_scan: global_best_index={best_idx} delay_ms={best_delay}")
delay_by_name = {name: (delay, idx) for delay, idx, name in results}

changed = 0
eligible = 0
for group_index, (group_name, group_type, options) in enumerate(groups, 1):
    if group_type != "Selector":
        continue
    candidates = []
    for option in options:
        if option in delay_by_name:
            delay, idx = delay_by_name[option]
            candidates.append((delay, idx, option))
    if not candidates:
        continue
    candidates.sort()
    delay, idx, selected_name = candidates[0]
    eligible += 1
    print(f"selector_scan: selector_group_index={group_index} selected_proxy_index={idx} delay_ms={delay}")
    if dry_run:
        continue
    try:
        request("/proxies/" + urllib.parse.quote(group_name, safe=""), method="PUT", body={"name": selected_name}, timeout=5)
        changed += 1
    except urllib.error.HTTPError:
        pass
    except Exception:
        pass

if dry_run:
    print(f"selector_scan: dry_run eligible_selector_groups={eligible}")
else:
    print(f"selector_scan: selector_groups_changed={changed} eligible={eligible}")
    if eligible and not changed:
        raise SystemExit(1)
PY_SELECT
