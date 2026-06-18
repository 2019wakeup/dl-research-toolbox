#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
QUICK=0
CHECK_PYTHON=1
CHECK_CODEX_LOGIN=1
CHECK_CODEX_DOCTOR=1
REPAIR_CODEX_LOGIN=0
STRICT=1
SOURCE_PROXY=1
FAILURES=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/doctor.sh [options]

Run post-install health checks through one entrypoint.

Options:
  --quick       Run machine, mihomo, Codex login egress, and official Codex doctor checks only; skip deep registry checks.
  --no-python   Skip Python research tools import checks in deep mode.
  --no-codex-login  Skip Codex ChatGPT device-code login egress check.
  --no-codex-doctor  Skip official Codex CLI doctor runtime check.
  --repair-codex-login  Repair mihomo selector for Codex login egress.
  --no-source-proxy  Do not source scripts/proxy-on.sh before checks.
  --no-strict        Print failures but exit zero.
  -h, --help         Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --no-python) CHECK_PYTHON=0; shift ;;
    --no-codex-login) CHECK_CODEX_LOGIN=0; shift ;;
    --no-codex-doctor) CHECK_CODEX_DOCTOR=0; shift ;;
    --repair-codex-login) CHECK_CODEX_LOGIN=1; REPAIR_CODEX_LOGIN=1; shift ;;
    --no-source-proxy) SOURCE_PROXY=0; shift ;;
    --no-strict) STRICT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

run_check() {
  local label="$1"
  shift
  local rule="========================================================================"
  echo
  echo "$rule"
  echo "DIAGNOSTIC: $label"
  echo "$rule"
  if "$@"; then
    echo
    echo "[ok] $label"
  else
    echo
    echo "[fail] $label" >&2
    FAILURES=$((FAILURES + 1))
  fi
  echo "$rule"
}

codex_doctor_check() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "codex not found on PATH" >&2
    return 1
  fi
  codex doctor --ascii --summary
}

cd "$REPO_ROOT"
if [ "$SOURCE_PROXY" -eq 1 ] && [ -f scripts/proxy-on.sh ]; then
  # shellcheck disable=SC1091
  source scripts/proxy-on.sh >/dev/null
fi
run_check "machine check" bash scripts/check-machine.sh
run_check "mihomo proxy check" bash scripts/mihomo-status.sh --strict --test-proxy
if [ "$CHECK_CODEX_DOCTOR" -eq 1 ]; then
  run_check "official Codex CLI doctor" codex_doctor_check
fi
if [ "$CHECK_CODEX_LOGIN" -eq 1 ]; then
  codex_login_args=(check --no-source-proxy)
  if [ "$REPAIR_CODEX_LOGIN" -eq 1 ]; then
    codex_login_args=(repair --no-source-proxy)
  fi
  run_check "Codex ChatGPT device-code login egress" bash scripts/codex-login-egress-check.sh "${codex_login_args[@]}"
fi

if [ "$QUICK" -eq 0 ]; then
  deep_args=(--no-codex-login)
  if [ "$CHECK_PYTHON" -eq 0 ]; then
    deep_args+=(--no-python)
  fi
  run_check "deep proxy check" bash scripts/verify-proxy-deep.sh "${deep_args[@]}"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "Doctor checks passed."
else
  echo "Doctor checks failed: $FAILURES issue(s)." >&2
fi

if [ "$STRICT" -eq 1 ] && [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
