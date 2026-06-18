#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ACTION="check"
STRICT=1
SOURCE_PROXY=1
SCAN_LIMIT="${CODEX_LOGIN_SCAN_LIMIT:-120}"
PROBE_TIMEOUT="${CODEX_LOGIN_PROBE_TIMEOUT:-8}"
PREFILTER_TIMEOUT="${CODEX_LOGIN_PREFILTER_TIMEOUT:-12}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/codex-login-egress-check.sh [check|repair] [options]

Verify or repair the proxy egress used by `codex login --device-auth`.
This check intentionally captures and redacts device-code output. It may create
short-lived unused device codes, but it never prints the code.

Actions:
  check              Test the current proxy egress. Default.
  repair             Scan mihomo selector candidates and switch to one that can
                     request a Codex device code.

Options:
  --scan-limit N     Maximum leaf proxies to try in repair mode. Default: 120.
  --probe-timeout S  Seconds to wait for each Codex device-code probe. Default: 8.
  --prefilter-timeout S  Seconds for Cloudflare challenge prefilter. Default: 12.
  --no-source-proxy  Do not source scripts/proxy-on.sh before checks.
  --no-strict        Print failures but exit zero.
  -h, --help         Show this help.

Environment:
  CODEX_LOGIN_SCAN_LIMIT
  CODEX_LOGIN_PROBE_TIMEOUT
  CODEX_LOGIN_PREFILTER_TIMEOUT
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    check|repair) ACTION="$1"; shift ;;
    --scan-limit) SCAN_LIMIT="${2:-}"; shift 2 ;;
    --probe-timeout) PROBE_TIMEOUT="${2:-}"; shift 2 ;;
    --prefilter-timeout) PREFILTER_TIMEOUT="${2:-}"; shift 2 ;;
    --no-source-proxy) SOURCE_PROXY=0; shift ;;
    --no-strict) STRICT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$SCAN_LIMIT" in ''|*[!0-9]*) echo "--scan-limit must be a positive integer." >&2; exit 2 ;; esac
case "$PROBE_TIMEOUT" in ''|*[!0-9]*) echo "--probe-timeout must be a positive integer." >&2; exit 2 ;; esac
case "$PREFILTER_TIMEOUT" in ''|*[!0-9]*) echo "--prefilter-timeout must be a positive integer." >&2; exit 2 ;; esac
[ "$SCAN_LIMIT" -gt 0 ] || SCAN_LIMIT=120
[ "$PROBE_TIMEOUT" -gt 0 ] || PROBE_TIMEOUT=8
[ "$PREFILTER_TIMEOUT" -gt 0 ] || PREFILTER_TIMEOUT=12

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

if [ "$SOURCE_PROXY" -eq 1 ] && [ -f "$SCRIPT_DIR/proxy-on.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/proxy-on.sh" >/dev/null
fi

CODEX_LOGIN_ACTION="$ACTION" \
CODEX_LOGIN_STRICT="$STRICT" \
CODEX_LOGIN_SCAN_LIMIT="$SCAN_LIMIT" \
CODEX_LOGIN_PROBE_TIMEOUT="$PROBE_TIMEOUT" \
CODEX_LOGIN_PREFILTER_TIMEOUT="$PREFILTER_TIMEOUT" \
python3 - <<'PY_CODEX_LOGIN_EGRESS'
import json
import os
import re
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path

ACTION = os.environ["CODEX_LOGIN_ACTION"]
STRICT = os.environ.get("CODEX_LOGIN_STRICT") == "1"
SCAN_LIMIT = int(os.environ["CODEX_LOGIN_SCAN_LIMIT"])
PROBE_TIMEOUT = int(os.environ["CODEX_LOGIN_PROBE_TIMEOUT"])
PREFILTER_TIMEOUT = int(os.environ["CODEX_LOGIN_PREFILTER_TIMEOUT"])

DEVICE_URL = "https://chatgpt.com/backend-api/codex/deviceauth/usercode"


def print_ok(message: str) -> None:
    print(f"[ok]   {message}")


def print_fail(message: str) -> None:
    print(f"[fail] {message}")


def sanitize(text: str) -> str:
    text = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)
    text = re.sub(r"\b[A-Z0-9]{4}-[A-Z0-9]{5}\b", "[REDACTED-CODE]", text)
    return text


def curl_prefilter() -> tuple[str, str]:
    cmd = ["curl", "-sS", "-I", "-L", "--max-time", str(PREFILTER_TIMEOUT), DEVICE_URL]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=PREFILTER_TIMEOUT + 4)
    except FileNotFoundError:
        return "no_curl", "curl not found"
    except subprocess.TimeoutExpired:
        return "timeout", "curl prefilter timed out"
    out = proc.stdout or ""
    lower = out.lower()
    status = "none"
    for line in out.splitlines():
        if line.startswith("HTTP/"):
            status = line.strip()
    if "cf-mitigated: challenge" in lower:
        return "cloudflare_challenge", status
    if proc.returncode != 0:
        return "curl_error", status
    return "not_challenged", status


def codex_device_probe() -> tuple[str, str]:
    env = os.environ.copy()
    env["TERM"] = env.get("TERM") if env.get("TERM") and env.get("TERM") != "dumb" else "xterm-256color"
    env["NO_COLOR"] = "1"
    cmd = ["timeout", f"{PROBE_TIMEOUT}s", "codex", "login", "--device-auth"]
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=PROBE_TIMEOUT + 5,
            env=env,
        )
    except FileNotFoundError:
        return "no_codex", "codex not found"
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        cleaned = sanitize(output)
        if "https://auth.openai.com/codex/device" in cleaned and "one-time code" in cleaned.lower():
            return "success", "device code request succeeded (code redacted)"
        return "timeout", "codex device-auth probe timed out"

    cleaned = sanitize(proc.stdout or "")
    if "https://auth.openai.com/codex/device" in cleaned and "one-time code" in cleaned.lower():
        return "success", "device code request succeeded (code redacted)"
    if "device code request failed with status 403" in cleaned or "403 Forbidden" in cleaned:
        return "forbidden", "device code request failed with 403"
    if "failed to request device code" in cleaned or "Error logging in with device code" in cleaned:
        first = next((line.strip() for line in cleaned.splitlines() if line.strip()), "device code request failed")
        return "error", first[:180]
    if proc.returncode == 124:
        return "timeout", "codex device-auth probe timed out before a code appeared"
    return "unknown", "unexpected codex login output"


def check_current(verbose: bool = True) -> tuple[bool, str]:
    pre_state, pre_detail = curl_prefilter()
    if verbose:
        print(f"codex_login_egress: prefilter={pre_state} status={pre_detail}")
    state, detail = codex_device_probe()
    if state == "success":
        if verbose:
            print_ok("Codex device-code login egress works; code output was redacted")
        return True, state
    if verbose:
        print_fail(f"Codex device-code login egress failed: {detail}")
    return False, state


def read_yaml_value(path: Path, key: str) -> str:
    if not path.exists():
        return ""
    for line in path.read_text(errors="ignore").splitlines():
        if line.startswith(key + ":"):
            return line.split(":", 1)[1].strip().strip("\"'")
    return ""


def controller_request(base: str, headers: dict[str, str], path: str, method: str = "GET", body=None, timeout: int = 8):
    data = None
    hdrs = dict(headers)
    if body is not None:
        data = json.dumps(body).encode()
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, method=method, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return json.loads(raw.decode()) if raw else None


def repair() -> tuple[bool, str]:
    print("codex_login_egress: checking current selector before scanning")
    ok, reason = check_current(verbose=True)
    if ok:
        return True, "current_ok"

    config = Path(os.environ.get("MIHOMO_CONFIG_FILE", str(Path.home() / ".config/mihomo/config.yaml")))
    if not config.exists():
        print_fail(f"mihomo config missing: {config}")
        return False, "missing_config"

    controller = read_yaml_value(config, "external-controller") or "127.0.0.1:9090"
    secret = read_yaml_value(config, "secret")
    if not controller.startswith(("http://", "https://")):
        controller = "http://" + controller
    controller = controller.replace("0.0.0.0", "127.0.0.1").rstrip("/")
    headers = {"Authorization": f"Bearer {secret}"} if secret else {}

    def req(path: str, method: str = "GET", body=None, timeout: int = 8):
        return controller_request(controller, headers, path, method=method, body=body, timeout=timeout)

    def put_proxy(group: str, name: str) -> bool:
        try:
            req("/proxies/" + urllib.parse.quote(group, safe=""), method="PUT", body={"name": name}, timeout=5)
            return True
        except Exception:
            return False

    try:
        data = req("/proxies")
    except Exception as exc:
        print_fail(f"mihomo controller unavailable: {type(exc).__name__}: {exc}")
        return False, "controller_error"

    proxies = data.get("proxies", {})
    groups = []
    leaf = []
    for name, obj in proxies.items():
        if "all" in obj:
            groups.append((name, obj.get("type"), obj.get("all") or [], obj.get("now")))
        elif obj.get("type") not in ("Direct", "Reject"):
            leaf.append(name)

    selectors = [(g, t, opts, now) for g, t, opts, now in groups if t == "Selector"]
    original = {g: now for g, _, _, now in selectors if now}
    print(f"codex_login_egress: selectors={len(selectors)} leaf_proxies={len(leaf)} scan_limit={min(SCAN_LIMIT, len(leaf))}")

    candidates = []
    seen = set()
    for leaf_index, name in enumerate(leaf, 1):
        eligible = [g for g, _, opts, _ in selectors if name in opts]
        if eligible and name not in seen:
            seen.add(name)
            candidates.append((leaf_index, name, eligible))

    for ordinal, (leaf_index, name, eligible) in enumerate(candidates[:SCAN_LIMIT], 1):
        for group in eligible:
            put_proxy(group, name)
        time.sleep(0.35)
        pre_state, pre_detail = curl_prefilter()
        state, detail = codex_device_probe()
        print(f"codex_login_egress: candidate={ordinal} leaf_index={leaf_index} groups={len(eligible)} prefilter={pre_state} result={state}")
        if state == "success":
            for group in eligible:
                put_proxy(group, name)
            print_ok(f"selected Codex-login-capable proxy candidate={ordinal} leaf_index={leaf_index} groups={len(eligible)}")
            return True, "selected"

    for group, name in original.items():
        put_proxy(group, name)
    print_fail("no Codex-login-capable proxy candidate found; restored original selectors")
    return False, "not_found"


if ACTION == "check":
    ok, _ = check_current(verbose=True)
else:
    ok, _ = repair()

if not ok and STRICT:
    raise SystemExit(1)
PY_CODEX_LOGIN_EGRESS
