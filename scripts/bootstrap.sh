#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=0
USE_NETWORK_TURBO="${USE_NETWORK_TURBO:-auto}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/bootstrap.sh [--dry-run]

Install generic research CLI tools only. This script intentionally does not
install conda, PyTorch, CUDA wheels, model checkpoints, or project packages.

Environment:
  USE_NETWORK_TURBO=auto|1|0  Source /etc/network_turbo when available.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
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

maybe_enable_network_turbo() {
  case "$USE_NETWORK_TURBO" in
    1|true|yes|auto)
      if [ -r /etc/network_turbo ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "[dry-run] source /etc/network_turbo"
          return
        fi
        # AutoDL-specific acceleration. The file is sourced, not copied.
        # shellcheck disable=SC1091
        source /etc/network_turbo
        echo "Enabled /etc/network_turbo for this bootstrap process."
      elif [ "$USE_NETWORK_TURBO" != "auto" ]; then
        echo "USE_NETWORK_TURBO requested, but /etc/network_turbo is unavailable." >&2
      fi
      ;;
    0|false|no) ;;
    *)
      echo "Invalid USE_NETWORK_TURBO=$USE_NETWORK_TURBO" >&2
      exit 2
      ;;
  esac
}

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found. Install the package list in this script with your OS package manager." >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo not found and current user is not root." >&2
    exit 1
  fi
  SUDO=(sudo)
fi

PACKAGES=(
  aria2
  build-essential
  ca-certificates
  cmake
  curl
  dnsutils
  fzf
  git
  git-lfs
  htop
  iproute2
  jq
  lsof
  make
  net-tools
  openssh-client
  pkg-config
  ripgrep
  rsync
  tar
  tmux
  unzip
  wget
  xz-utils
  zip
)

maybe_enable_network_turbo

run "${SUDO[@]}" apt-get update
run "${SUDO[@]}" apt-get install -y --no-install-recommends "${PACKAGES[@]}"

run mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" "$HOME/.local/state" "$HOME/.config/mihomo"

if command -v git-lfs >/dev/null 2>&1; then
  run git lfs install --skip-repo
fi

cat <<'DONE'
Bootstrap complete.

Next:
  bash scripts/mihomo-install.sh
  cp network/mihomo/config.yaml.example ~/.config/mihomo/config.yaml
  $EDITOR ~/.config/mihomo/config.yaml
DONE
