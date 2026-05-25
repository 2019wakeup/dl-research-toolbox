#!/usr/bin/env bash
set -Eeuo pipefail

STRICT_RUNTIME=0
FAILURES=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/check-codex-sandbox.sh [--strict-runtime]

Check the Codex sandbox prerequisite on Linux. Codex expects the OS package
manager's bubblewrap binary, exposed as bwrap on PATH. A runtime namespace
smoke test can still fail inside restricted containers even after bwrap is
installed; that is a host/container permission issue, not a PATH issue.

Options:
  --strict-runtime  Exit non-zero if the namespace smoke test fails.
  -h, --help        Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict-runtime) STRICT_RUNTIME=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ok() { printf '[ok]   %s\n' "$1"; }
warn() { printf '[warn] %s\n' "$1"; }
fail() { printf '[fail] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

echo "Codex sandbox prerequisite"
echo "--------------------------"

if ! command -v bwrap >/dev/null 2>&1; then
  fail "bwrap is not on PATH"
  echo "Install bubblewrap with the OS package manager, for example:"
  echo "  apt-get update && apt-get install -y bubblewrap"
  echo "Reference: https://developers.openai.com/codex/concepts/sandboxing#prerequisites"
  exit 1
fi

BWRAP_PATH="$(command -v bwrap)"
ok "bwrap found: $BWRAP_PATH"
if bwrap --version >/dev/null 2>&1; then
  ok "$(bwrap --version)"
else
  fail "bwrap --version failed"
fi

if command -v sysctl >/dev/null 2>&1; then
  for key in kernel.unprivileged_userns_clone user.max_user_namespaces; do
    if value="$(sysctl "$key" 2>/dev/null)"; then
      ok "$value"
    fi
  done
fi

if [ -r /proc/self/status ]; then
  status_lines="$(grep -E '^(NoNewPrivs|Seccomp|Seccomp_filters|CapEff|CapBnd):' /proc/self/status || true)"
  if [ -n "$status_lines" ]; then
    echo
    echo "Current process confinement"
    echo "$status_lines" | sed 's/^/  /'
  fi
fi

echo
echo "Namespace smoke test"
echo "--------------------"
binds=(--ro-bind /usr /usr)
for path in /bin /lib /lib64; do
  if [ -e "$path" ]; then
    binds+=(--ro-bind "$path" "$path")
  fi
done

log="$(mktemp)"
if bwrap "${binds[@]}" --proc /proc --dev /dev /usr/bin/true >"$log" 2>&1; then
  ok "bubblewrap can create a minimal sandbox"
  rm -f "$log"
else
  warn "bwrap is installed, but the namespace smoke test failed"
  sed -n '1,20p' "$log" | sed 's/^/  /'
  rm -f "$log"
  echo
  echo "This usually means the host/container policy blocks user or mount namespaces."
  echo "The Codex PATH prerequisite is fixed, but full bubblewrap sandbox execution"
  echo "requires the host to allow namespace creation."
  if [ "$STRICT_RUNTIME" -eq 1 ]; then
    FAILURES=$((FAILURES + 1))
  fi
fi

if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
