#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MIHOMO_FILE="${MIHOMO_YAML:-${MIHOMO_SUBSCRIPTION_FILE:-}}"
MIHOMO_URL="${MIHOMO_SUBSCRIPTION_URL:-}"
RUN_DOCTOR=1
RUN_BOOTSTRAP=1
DRY_RUN=0
SKIP_CODEX_CLI=0
SKIP_PYTHON_TOOLS=0
NETWORK_ARGS=()

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

usage() {
  cat <<'USAGE'
Usage: bash install.sh [options]

One-command setup for a fresh research machine. Prefer a local Clash/Mihomo
YAML file so proxy setup works before any network-sensitive downloads.

Common:
  bash install.sh --mihomo-yaml /root/mihomo.yaml
  cp /path/to/mihomo.yaml ./mihomo.yaml && bash install.sh

Options:
  --mihomo-yaml PATH       Local Clash/Mihomo YAML file. Recommended.
  --file PATH              Alias for --mihomo-yaml.
  --url URL                Subscription URL. Use only when direct access already works.
  --dry-run                Print planned setup without installing.
  --no-bootstrap           Stop after proxy, autostart, and Codex CLI setup.
  --proxy-only             Alias for --no-bootstrap.
  --replace-running        Replace an old mihomo process using the proxy port.
  --no-autostart           Do not install persistent mihomo startup.
  --autostart-mode MODE    auto, system, user, or profile. Default: auto.
  --no-codex-cli           Skip Codex CLI installation.
  --skip-python-tools      Skip the Python research tools venv during bootstrap.
  --skip-minimal-packages  Do not install ca-certificates/curl/gzip before mihomo.
  --no-doctor              Do not run scripts/doctor.sh after setup.
  -h, --help               Show this help.

Environment:
  MIHOMO_YAML              Default YAML path when --mihomo-yaml is omitted.
  INSTALL_PYTHON_TOOLS=0   Also skips the Python research tools venv.
USAGE
}

find_default_yaml() {
  local candidate
  for candidate in \
    "$SCRIPT_DIR/mihomo.yaml" \
    "$SCRIPT_DIR/mihomo.yml" \
    "$HOME/mihomo.yaml" \
    "$HOME/mihomo.yml"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mihomo-yaml|--file|--config-file|--yaml)
      MIHOMO_FILE="${2:-}"
      shift 2
      ;;
    --url)
      MIHOMO_URL="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      NETWORK_ARGS+=(--dry-run)
      shift
      ;;
    --no-bootstrap|--proxy-only)
      RUN_BOOTSTRAP=0
      NETWORK_ARGS+=(--no-bootstrap)
      shift
      ;;
    --replace-running)
      NETWORK_ARGS+=(--replace-running)
      shift
      ;;
    --no-autostart)
      NETWORK_ARGS+=(--no-autostart)
      shift
      ;;
    --autostart-mode)
      NETWORK_ARGS+=(--autostart-mode "${2:-}")
      shift 2
      ;;
    --no-autostart-linger)
      NETWORK_ARGS+=(--no-autostart-linger)
      shift
      ;;
    --no-codex-cli)
      SKIP_CODEX_CLI=1
      NETWORK_ARGS+=(--no-codex-cli)
      shift
      ;;
    --skip-python-tools)
      SKIP_PYTHON_TOOLS=1
      shift
      ;;
    --skip-minimal-packages)
      NETWORK_ARGS+=(--skip-minimal-packages)
      shift
      ;;
    --no-doctor)
      RUN_DOCTOR=0
      shift
      ;;
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

if [ -n "$MIHOMO_FILE" ] && [ -n "$MIHOMO_URL" ]; then
  echo "Use either --mihomo-yaml/--file or --url, not both." >&2
  exit 2
fi

if [ -z "$MIHOMO_FILE" ] && [ -z "$MIHOMO_URL" ]; then
  if detected="$(find_default_yaml)"; then
    MIHOMO_FILE="$detected"
    echo "Detected mihomo YAML: $MIHOMO_FILE"
  fi
fi

if [ -z "$MIHOMO_FILE" ] && [ -z "$MIHOMO_URL" ]; then
  echo "Missing mihomo YAML file." >&2
  echo "Pass --mihomo-yaml /path/to/mihomo.yaml, or place mihomo.yaml in this directory or in $HOME." >&2
  echo "Use --url only when direct access to the subscription endpoint already works." >&2
  exit 2
fi

if [ -n "$MIHOMO_FILE" ]; then
  NETWORK_ARGS+=(--file "$MIHOMO_FILE")
fi
if [ -n "$MIHOMO_URL" ]; then
  NETWORK_ARGS+=(--url "$MIHOMO_URL")
fi

if [ "${INSTALL_PYTHON_TOOLS:-1}" = "0" ]; then
  SKIP_PYTHON_TOOLS=1
fi

cli_install_args=()
if [ "$DRY_RUN" -eq 1 ]; then
  cli_install_args+=(--dry-run)
fi
bash "$SCRIPT_DIR/scripts/install-toolbox-cli.sh" "${cli_install_args[@]}"

if [ "$SKIP_PYTHON_TOOLS" -eq 1 ]; then
  INSTALL_PYTHON_TOOLS=0 bash "$SCRIPT_DIR/scripts/network-first-setup.sh" "${NETWORK_ARGS[@]}"
else
  bash "$SCRIPT_DIR/scripts/network-first-setup.sh" "${NETWORK_ARGS[@]}"
fi

if [ "$RUN_DOCTOR" -eq 1 ] && [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] skip scripts/doctor.sh"
elif [ "$RUN_DOCTOR" -eq 1 ]; then
  doctor_args=()
  if [ "$RUN_BOOTSTRAP" -eq 0 ] || [ "$SKIP_CODEX_CLI" -eq 1 ]; then
    doctor_args+=(--quick)
  fi
  if [ "$SKIP_PYTHON_TOOLS" -eq 1 ]; then
    doctor_args+=(--no-python)
  fi
  bash "$SCRIPT_DIR/scripts/doctor.sh" "${doctor_args[@]}"
fi
