#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=0
RUN_BOOTSTRAP=1
IMPORT_SUBSCRIPTION=1
REPLACE_RUNNING=0
INSTALL_MINIMAL=1

usage() {
  cat <<'USAGE'
Usage: bash scripts/network-first-setup.sh [--dry-run] [--no-bootstrap] [--no-import] [--replace-running] [--skip-minimal-packages]

Network-first setup. Install/configure mihomo before running the full bootstrap
so apt, uv, Python package downloads, GitHub, and Hugging Face access can use the proxy.

Options:
  --dry-run                Print planned steps. Does not install or import.
  --no-bootstrap           Stop after mihomo install/import and proxy check.
  --no-import              Install mihomo but do not import a subscription.
  --replace-running        Replace any existing mihomo process during import.
  --skip-minimal-packages  Do not try to install ca-certificates/curl/gzip first.
  -h, --help               Show this help.

Environment:
  USE_NETWORK_TURBO=auto|1|0  Passed through to mihomo-install/bootstrap.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-bootstrap) RUN_BOOTSTRAP=0; shift ;;
    --no-import) IMPORT_SUBSCRIPTION=0; shift ;;
    --replace-running) REPLACE_RUNNING=1; shift ;;
    --skip-minimal-packages) INSTALL_MINIMAL=0; shift ;;
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

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

install_minimal_packages() {
  if [ "$INSTALL_MINIMAL" -eq 0 ]; then
    return 0
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get not found; assuming curl/gzip/ca-certificates are already available."
    return 0
  fi

  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v gzip >/dev/null 2>&1 || missing+=(gzip)
  if [ ! -d /etc/ssl/certs ]; then
    missing+=(ca-certificates)
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  local sudo_cmd=()
  if [ "$(id -u)" -ne 0 ]; then
    sudo_cmd=(sudo)
  fi

  echo "Installing minimal network prerequisites before mihomo: ${missing[*]}"
  run "${sudo_cmd[@]}" apt-get update
  run "${sudo_cmd[@]}" apt-get install -y --no-install-recommends ca-certificates curl gzip
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] network-first setup order: minimal packages -> mihomo install -> subscription import -> proxy env -> full bootstrap"
fi

install_minimal_packages

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] bash scripts/mihomo-install.sh"
else
  (cd "$REPO_ROOT" && bash scripts/mihomo-install.sh)
fi

if [ "$IMPORT_SUBSCRIPTION" -eq 1 ]; then
  import_args=()
  if [ "$REPLACE_RUNNING" -eq 1 ]; then
    import_args+=(--replace-running)
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] bash scripts/mihomo-import-subscription.sh ${import_args[*]}"
  else
    (cd "$REPO_ROOT" && bash scripts/mihomo-import-subscription.sh "${import_args[@]}")
  fi
else
  echo "Skipping subscription import. Run scripts/mihomo-import-subscription.sh before bootstrap if network access is unreliable."
fi

if [ "$IMPORT_SUBSCRIPTION" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] source scripts/proxy-on.sh"
  else
    # Keep proxy variables in this script process so the full bootstrap below uses mihomo.
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/proxy-on.sh"
  fi
fi

if [ "$RUN_BOOTSTRAP" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    (cd "$REPO_ROOT" && USE_NETWORK_TURBO=0 bash scripts/bootstrap.sh --dry-run)
  else
    (cd "$REPO_ROOT" && USE_NETWORK_TURBO=0 bash scripts/bootstrap.sh)
  fi
fi

cat <<DONE
Network-first setup complete.

For this interactive shell, run:
  source scripts/proxy-on.sh

Validate any time with:
  bash scripts/mihomo-status.sh --strict --test-proxy
DONE
