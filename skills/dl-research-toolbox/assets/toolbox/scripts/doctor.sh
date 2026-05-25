#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
QUICK=0
CHECK_PYTHON=1
STRICT=1
SOURCE_PROXY=1
FAILURES=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/doctor.sh [options]

Run post-install health checks through one entrypoint.

Options:
  --quick       Run machine and mihomo proxy checks only; skip deep registry checks.
  --no-python   Skip Python research tools import checks in deep mode.
  --no-source-proxy  Do not source scripts/proxy-on.sh before checks.
  --no-strict        Print failures but exit zero.
  -h, --help         Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --no-python) CHECK_PYTHON=0; shift ;;
    --no-source-proxy) SOURCE_PROXY=0; shift ;;
    --no-strict) STRICT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

run_check() {
  local label="$1"
  shift
  echo
  echo "==> $label"
  if "$@"; then
    echo "[ok] $label"
  else
    echo "[fail] $label" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

cd "$REPO_ROOT"
if [ "$SOURCE_PROXY" -eq 1 ] && [ -f scripts/proxy-on.sh ]; then
  # shellcheck disable=SC1091
  source scripts/proxy-on.sh >/dev/null
fi
run_check "machine check" bash scripts/check-machine.sh
run_check "mihomo proxy check" bash scripts/mihomo-status.sh --strict --test-proxy

if [ "$QUICK" -eq 0 ]; then
  deep_args=()
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
