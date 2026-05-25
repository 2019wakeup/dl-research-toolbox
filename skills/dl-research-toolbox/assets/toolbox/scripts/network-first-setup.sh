#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=0
RUN_BOOTSTRAP=1
IMPORT_SUBSCRIPTION=1
INSTALL_CODEX_CLI=1
REPLACE_RUNNING=0
INSTALL_MINIMAL=1
INSTALL_AUTOSTART=1
MIHOMO_AUTOSTART_MODE="${MIHOMO_AUTOSTART_MODE:-auto}"
MIHOMO_AUTOSTART_ENABLE_LINGER="${MIHOMO_AUTOSTART_ENABLE_LINGER:-1}"
MIHOMO_FILE="${MIHOMO_SUBSCRIPTION_FILE:-}"
MIHOMO_URL="${MIHOMO_SUBSCRIPTION_URL:-}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/network-first-setup.sh [--dry-run] [--file PATH | --url URL] [--no-bootstrap] [--no-import] [--no-codex-cli] [--no-autostart] [--replace-running] [--skip-minimal-packages]

Network-first setup. Install/configure mihomo before running the full bootstrap
so apt, uv, Python package downloads, GitHub, and Hugging Face access can use the proxy.

Options:
  --dry-run                Print planned steps. Does not install or import.
  --file PATH             Import a local Clash/Mihomo YAML file. Recommended for cold-start machines.
  --url URL                Import a subscription URL. Use only when direct network access already works.
  --no-bootstrap           Stop after mihomo install/import, proxy check, and Codex CLI install.
  --no-import              Install mihomo but do not import a subscription.
  --no-codex-cli           Skip Codex CLI installation before full bootstrap.
  --no-autostart           Do not install mihomo autostart after import. Autostart is on by default.
  --autostart-mode MODE    auto, system, user, or profile. Default: auto.
  --no-autostart-linger    Do not pass --enable-linger when auto/user autostart is selected.
  --replace-running        Replace any existing mihomo process during import.
  --skip-minimal-packages  Do not try to install ca-certificates/curl/gzip first.
  -h, --help               Show this help.

Environment:
  USE_NETWORK_TURBO=auto|1|0  Passed through to mihomo-install/bootstrap.
  MIHOMO_AUTOSTART_MODE       Default autostart mode: auto.
  MIHOMO_AUTOSTART_ENABLE_LINGER=1|0  Default: 1.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --file|--config-file|--yaml) MIHOMO_FILE="${2:-}"; shift 2 ;;
    --url) MIHOMO_URL="${2:-}"; shift 2 ;;
    --no-bootstrap) RUN_BOOTSTRAP=0; shift ;;
    --no-import) IMPORT_SUBSCRIPTION=0; shift ;;
    --no-codex-cli) INSTALL_CODEX_CLI=0; shift ;;
    --no-autostart) INSTALL_AUTOSTART=0; shift ;;
    --autostart-mode) MIHOMO_AUTOSTART_MODE="${2:-}"; shift 2 ;;
    --no-autostart-linger) MIHOMO_AUTOSTART_ENABLE_LINGER=0; shift ;;
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

case "$MIHOMO_AUTOSTART_MODE" in
  auto|system|user|profile) ;;
  *) echo "Invalid --autostart-mode: $MIHOMO_AUTOSTART_MODE" >&2; exit 2 ;;
esac

case "$MIHOMO_AUTOSTART_ENABLE_LINGER" in
  1|true|yes|on) MIHOMO_AUTOSTART_ENABLE_LINGER=1 ;;
  0|false|no|off) MIHOMO_AUTOSTART_ENABLE_LINGER=0 ;;
  *) echo "Invalid MIHOMO_AUTOSTART_ENABLE_LINGER: $MIHOMO_AUTOSTART_ENABLE_LINGER" >&2; exit 2 ;;
esac

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
  order="minimal packages -> mihomo install"
  if [ "$IMPORT_SUBSCRIPTION" -eq 1 ]; then
    order="$order -> local YAML config import"
    if [ "$INSTALL_AUTOSTART" -eq 1 ]; then
      order="$order -> mihomo autostart"
    fi
    order="$order -> proxy env"
  fi
  if [ "$INSTALL_CODEX_CLI" -eq 1 ]; then
    order="$order -> Codex CLI"
  fi
  if [ "$RUN_BOOTSTRAP" -eq 1 ]; then
    order="$order -> full bootstrap"
  fi
  echo "[dry-run] network-first setup order: $order"
fi

install_minimal_packages

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] bash scripts/mihomo-install.sh"
else
  (cd "$REPO_ROOT" && bash scripts/mihomo-install.sh)
fi

if [ "$IMPORT_SUBSCRIPTION" -eq 1 ]; then
  import_args=()
  if [ -n "$MIHOMO_FILE" ] && [ -n "$MIHOMO_URL" ]; then
    echo "Use either --file or --url, not both." >&2
    exit 2
  fi
  if [ -n "$MIHOMO_FILE" ]; then
    import_args+=(--file "$MIHOMO_FILE")
  fi
  if [ -n "$MIHOMO_URL" ]; then
    import_args+=(--url "$MIHOMO_URL")
  fi
  if [ "$REPLACE_RUNNING" -eq 1 ]; then
    import_args+=(--replace-running)
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] bash scripts/mihomo-import-subscription.sh ${import_args[*]}"
  else
    (cd "$REPO_ROOT" && bash scripts/mihomo-import-subscription.sh "${import_args[@]}")
  fi
else
  echo "Skipping subscription import. Run scripts/mihomo-import-subscription.sh --file /path/to/mihomo.yaml before bootstrap if network access is unreliable."
fi

if [ "$IMPORT_SUBSCRIPTION" -eq 1 ] && [ "$INSTALL_AUTOSTART" -eq 1 ]; then
  autostart_args=(install --mode "$MIHOMO_AUTOSTART_MODE")
  if [ "$MIHOMO_AUTOSTART_ENABLE_LINGER" -eq 1 ]; then
    autostart_args+=(--enable-linger)
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] bash scripts/mihomo-autostart.sh ${autostart_args[*]}"
  else
    (cd "$REPO_ROOT" && bash scripts/mihomo-autostart.sh "${autostart_args[@]}")
  fi
elif [ "$IMPORT_SUBSCRIPTION" -eq 1 ]; then
  echo "Skipping mihomo autostart. Enable later with: bash scripts/mihomo-autostart.sh install --mode auto --enable-linger"
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

if [ "$INSTALL_CODEX_CLI" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] bash scripts/install-codex-cli.sh"
  else
    (cd "$REPO_ROOT" && bash scripts/install-codex-cli.sh)
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
  bash scripts/mihomo-autostart.sh status
DONE
