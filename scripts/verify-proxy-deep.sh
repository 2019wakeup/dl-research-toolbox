#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STRICT=1
SOURCE_PROXY=1
CHECK_PYTHON=1
CHECK_CODEX_LOGIN=1
REPAIR_CODEX_LOGIN=0
GIT_REMOTE="${VERIFY_PROXY_GIT_REMOTE:-https://github.com/openai/codex.git}"
NPM_PACKAGE="${VERIFY_PROXY_NPM_PACKAGE:-@openai/codex}"
URLS=(
  https://github.com
  https://api.github.com
  https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore
  https://huggingface.co
  'https://huggingface.co/api/models?limit=1'
  https://pypi.org/pypi/pip/json
  https://registry.npmjs.org/@openai/codex
)
FAILURES=0

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

usage() {
  cat <<'USAGE'
Usage: bash scripts/verify-proxy-deep.sh [options]

Deep proxy verification for a freshly migrated research machine. This checks
mihomo, proxy environment variables, curl egress, git over HTTPS, npm registry
access, Codex CLI, uv, and the optional Python research tools venv.

Options:
  --strict             Exit non-zero on failures. Default.
  --no-strict          Print failures but exit zero.
  --no-source-proxy    Do not source scripts/proxy-on.sh before checks.
  --no-python          Skip Python research tools import check.
  --no-codex-login     Skip Codex ChatGPT device-code login egress check.
  --repair-codex-login Repair mihomo selector before checking Codex login egress.
  --url URL            Add an extra URL to test with curl.
  --git-remote URL     Git remote for ls-remote. Default: openai/codex.
  --npm-package NAME   npm package for npm view. Default: @openai/codex.
  -h, --help           Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --no-strict) STRICT=0; shift ;;
    --no-source-proxy) SOURCE_PROXY=0; shift ;;
    --no-python) CHECK_PYTHON=0; shift ;;
    --no-codex-login) CHECK_CODEX_LOGIN=0; shift ;;
    --repair-codex-login) CHECK_CODEX_LOGIN=1; REPAIR_CODEX_LOGIN=1; shift ;;
    --url) URLS+=("${2:-}"); shift 2 ;;
    --git-remote) GIT_REMOTE="${2:-}"; shift 2 ;;
    --npm-package) NPM_PACKAGE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

mark_fail() { FAILURES=$((FAILURES + 1)); }
ok() { printf '[ok]   %s\n' "$1"; }
fail() { printf '[fail] %s\n' "$1"; mark_fail; }
skip() { printf '[skip] %s\n' "$1"; }

run_quiet() {
  local label="$1"
  shift
  local log
  log="$(mktemp)"
  if "$@" >"$log" 2>&1; then
    ok "$label"
    rm -f "$log"
  else
    fail "$label"
    sed -n '1,40p' "$log" | sed 's/^/  /'
    rm -f "$log"
  fi
}

if [ "$SOURCE_PROXY" -eq 1 ]; then
  if [ -f "$SCRIPT_DIR/proxy-on.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/proxy-on.sh" >/dev/null
    ok "proxy environment sourced"
  else
    fail "missing scripts/proxy-on.sh"
  fi
fi

echo "Proxy environment"
echo "-----------------"
for name in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; do
  if [ -n "${!name:-}" ]; then ok "$name is set"; else fail "$name is unset"; fi
done

echo
echo "mihomo"
echo "------"
if [ -x "$SCRIPT_DIR/mihomo-status.sh" ]; then
  run_quiet "mihomo strict status and proxy egress" bash "$SCRIPT_DIR/mihomo-status.sh" --strict --test-proxy --no-log
else
  fail "missing scripts/mihomo-status.sh"
fi

echo
echo "HTTP egress"
echo "-----------"
curl_egress() {
  local url="$1"
  local code
  code="$(curl -sS -L --connect-timeout 8 --max-time 30 -o /dev/null -w '%{http_code}' "$url")" || return 1
  case "$code" in
    2*|3*|4*) return 0 ;;
    *) echo "unexpected HTTP status: $code" >&2; return 1 ;;
  esac
}

if command -v curl >/dev/null 2>&1; then
  for url in "${URLS[@]}"; do
    [ -z "$url" ] && continue
    run_quiet "curl $url" curl_egress "$url"
  done
else
  fail "curl not found"
fi

echo
echo "Git and npm"
echo "-----------"
if command -v git >/dev/null 2>&1; then
  run_quiet "git ls-remote $GIT_REMOTE HEAD" git ls-remote "$GIT_REMOTE" HEAD
else
  fail "git not found"
fi

if command -v npm >/dev/null 2>&1; then
  run_quiet "npm view $NPM_PACKAGE version" npm view "$NPM_PACKAGE" version
else
  fail "npm not found"
fi

echo
echo "CLI tools"
echo "---------"
if command -v codex >/dev/null 2>&1; then run_quiet "codex --version" codex --version; else fail "codex not found"; fi
if [ "$CHECK_CODEX_LOGIN" -eq 1 ]; then
  if [ -x "$SCRIPT_DIR/codex-login-egress-check.sh" ]; then
    if [ "$REPAIR_CODEX_LOGIN" -eq 1 ]; then
      run_quiet "Codex ChatGPT device-code login egress repair" bash "$SCRIPT_DIR/codex-login-egress-check.sh" repair --no-source-proxy
    else
      run_quiet "Codex ChatGPT device-code login egress" bash "$SCRIPT_DIR/codex-login-egress-check.sh" check --no-source-proxy
    fi
  else
    fail "missing scripts/codex-login-egress-check.sh"
  fi
else
  skip "Codex ChatGPT device-code login egress check disabled"
fi
if [ -f "$SCRIPT_DIR/check-codex-sandbox.sh" ]; then
  run_quiet "Codex sandbox prerequisites" bash "$SCRIPT_DIR/check-codex-sandbox.sh"
else
  fail "missing scripts/check-codex-sandbox.sh"
fi
if command -v uv >/dev/null 2>&1; then run_quiet "uv --version" uv --version; else fail "uv not found"; fi

if [ "$CHECK_PYTHON" -eq 1 ]; then
  echo
  echo "Python tools"
  echo "------------"
  PYTHON_TOOLS_VENV="${PYTHON_TOOLS_VENV:-$HOME/.local/venvs/research-tools}"
  if [ -x "$PYTHON_TOOLS_VENV/bin/python" ]; then
    run_quiet "research-tools imports" "$PYTHON_TOOLS_VENV/bin/python" - <<'PY_IMPORTS'
import importlib.util
mods = ["huggingface_hub", "datasets", "gdown", "nvitop", "pytest", "ruff"]
missing = [m for m in mods if importlib.util.find_spec(m) is None]
if missing:
    raise SystemExit("missing: " + ", ".join(missing))
PY_IMPORTS
  else
    fail "Python tools venv missing: $PYTHON_TOOLS_VENV"
  fi
else
  skip "Python tools check disabled"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "Deep proxy verification passed."
else
  echo "Deep proxy verification failed: $FAILURES issue(s)." >&2
fi

if [ "$STRICT" -eq 1 ] && [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
