#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=0
USE_NETWORK_TURBO="${USE_NETWORK_TURBO:-auto}"
INSTALL_PYTHON_TOOLS="${INSTALL_PYTHON_TOOLS:-1}"
PYTHON_TOOLS_VENV="${PYTHON_TOOLS_VENV:-$HOME/.local/venvs/research-tools}"
UV_INSTALL_URL="${UV_INSTALL_URL:-https://astral.sh/uv/install.sh}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: bash scripts/bootstrap.sh [--dry-run]

Install generic research CLI tools and a trimmed Python tools venv. This script
intentionally does not install conda, PyTorch, CUDA wheels, model checkpoints,
or project packages.

Environment:
  USE_NETWORK_TURBO=auto|1|0  Source /etc/network_turbo when available.
  INSTALL_PYTHON_TOOLS=1|0    Install trimmed Python research tools with uv.
  PYTHON_TOOLS_VENV=PATH      Default: ~/.local/venvs/research-tools.
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


install_uv() {
  if command -v uv >/dev/null 2>&1; then
    echo "uv already installed: $(command -v uv)"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] curl -fsSL $UV_INSTALL_URL -o /tmp/uv-install.sh"
    echo "[dry-run] sh /tmp/uv-install.sh"
    return 0
  fi

  local installer
  installer="$(mktemp)"
  curl -fsSL "$UV_INSTALL_URL" -o "$installer"
  sh "$installer"
  rm -f "$installer"

  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac

  if ! command -v uv >/dev/null 2>&1; then
    echo "uv installation finished, but uv is not on PATH. Add ~/.local/bin to PATH." >&2
    exit 1
  fi
}

install_python_tools() {
  case "$INSTALL_PYTHON_TOOLS" in
    1|true|yes) ;;
    0|false|no)
      echo "Skipping Python research tools because INSTALL_PYTHON_TOOLS=$INSTALL_PYTHON_TOOLS."
      return 0
      ;;
    *)
      echo "Invalid INSTALL_PYTHON_TOOLS=$INSTALL_PYTHON_TOOLS" >&2
      exit 2
      ;;
  esac

  local req
  req="$REPO_ROOT/requirements/research-tools.txt"
  if [ ! -f "$req" ]; then
    echo "Missing requirements file: $req" >&2
    exit 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] uv venv $PYTHON_TOOLS_VENV"
    echo "[dry-run] uv pip install --python $PYTHON_TOOLS_VENV/bin/python -r $req"
    return 0
  fi

  uv venv "$PYTHON_TOOLS_VENV"
  uv pip install --python "$PYTHON_TOOLS_VENV/bin/python" -r "$req"

  mkdir -p "$HOME/.local/bin"
  for tool in nvitop gdown ruff pytest tensorboard huggingface-cli; do
    if [ -x "$PYTHON_TOOLS_VENV/bin/$tool" ]; then
      ln -sfn "$PYTHON_TOOLS_VENV/bin/$tool" "$HOME/.local/bin/$tool"
    fi
  done

  cat <<TOOLS_DONE
Python research tools installed in:
  $PYTHON_TOOLS_VENV

Activate when needed:
  source $PYTHON_TOOLS_VENV/bin/activate

Common CLI symlinks were written to ~/.local/bin when available.
TOOLS_DONE
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
  gh
  git
  git-lfs
  htop
  iproute2
  jq
  lsof
  make
  net-tools
  npm
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

run mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" "$HOME/.local/state" "$HOME/.config/mihomo" "$HOME/.local/venvs"

if command -v git-lfs >/dev/null 2>&1; then
  run git lfs install --skip-repo
fi

install_uv
install_python_tools

cat <<'DONE'
Bootstrap complete.

Installed base tools include gh, npm, uv, and a trimmed Python research tools venv.

Next:
  bash scripts/mihomo-install.sh
  bash scripts/mihomo-import-subscription.sh
  source scripts/proxy-on.sh
DONE
