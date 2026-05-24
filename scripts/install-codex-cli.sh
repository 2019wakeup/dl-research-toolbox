#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=0
CODEX_NPM_PACKAGE="${CODEX_NPM_PACKAGE:-@openai/codex}"
CODEX_INSTALL_PREFIX="${CODEX_INSTALL_PREFIX:-$HOME/.local}"
CODEX_NODE_MAJOR="${CODEX_NODE_MAJOR:-22}"
CODEX_MIN_NODE_MAJOR="${CODEX_MIN_NODE_MAJOR:-16}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/install-codex-cli.sh [--dry-run]

Install OpenAI Codex CLI after proxy setup and before the rest of the toolbox
bootstrap. The default install target is user-local: ~/.local/bin/codex.

Environment:
  CODEX_NPM_PACKAGE       default: @openai/codex
  CODEX_INSTALL_PREFIX    default: ~/.local
  CODEX_NODE_MAJOR        default: 22, used when Node.js is missing or too old
  CODEX_MIN_NODE_MAJOR    default: 16, minimum required for Codex CLI
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

ensure_path_now() {
  case ":$PATH:" in
    *":$CODEX_INSTALL_PREFIX/bin:"*) ;;
    *) export PATH="$CODEX_INSTALL_PREFIX/bin:$PATH" ;;
  esac
}

ensure_path_persisted() {
  local profile="$HOME/.bashrc"
  local line
  if [ "$CODEX_INSTALL_PREFIX" = "$HOME/.local" ]; then
    line='export PATH="$HOME/.local/bin:$PATH"'
  else
    line="export PATH=\"$CODEX_INSTALL_PREFIX/bin:\$PATH\""
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] ensure $profile contains: $line"
    return 0
  fi

  touch "$profile"
  if ! grep -Fqx "$line" "$profile"; then
    {
      printf '\n# Added by dl-research-toolbox for user-local CLI tools.\n'
      printf '%s\n' "$line"
    } >> "$profile"
  fi
}

find_codex() {
  ensure_path_now
  command -v codex 2>/dev/null || true
}

node_major() {
  if ! command -v node >/dev/null 2>&1; then
    return 1
  fi
  node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null
}

repair_dpkg_state() {
  local -n sudo_cmd_ref=$1
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] dpkg --configure -a"
    echo "[dry-run] apt-get install -f -y"
    return 0
  fi
  "${sudo_cmd_ref[@]}" dpkg --configure -a || true
  "${sudo_cmd_ref[@]}" apt-get install -f -y || true
}

remove_debian_node_packages() {
  local -n sudo_cmd_ref=$1
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] apt-get remove -y libnode-dev libnode72 nodejs npm"
    return 0
  fi
  "${sudo_cmd_ref[@]}" apt-get remove -y libnode-dev libnode72 nodejs npm || true
}

install_modern_node() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Node.js is missing or too old, and apt-get is unavailable." >&2
    exit 1
  fi

  local sudo_cmd=()
  if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
      echo "sudo not found and current user is not root." >&2
      exit 1
    fi
    sudo_cmd=(sudo)
  fi

  echo "Installing Node.js ${CODEX_NODE_MAJOR}.x for Codex CLI."
  repair_dpkg_state sudo_cmd
  run "${sudo_cmd[@]}" apt-get update
  run "${sudo_cmd[@]}" apt-get install -y --no-install-recommends ca-certificates curl gnupg

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] curl -fsSL https://deb.nodesource.com/setup_${CODEX_NODE_MAJOR}.x -o /tmp/nodesource_setup.sh"
    echo "[dry-run] bash /tmp/nodesource_setup.sh"
  else
    local setup_script
    setup_script="$(mktemp)"
    curl -fsSL "https://deb.nodesource.com/setup_${CODEX_NODE_MAJOR}.x" -o "$setup_script"
    bash "$setup_script"
    rm -f "$setup_script"
  fi

  remove_debian_node_packages sudo_cmd
  run "${sudo_cmd[@]}" apt-get install -y --no-install-recommends nodejs
  hash -r 2>/dev/null || true
}

ensure_npm() {
  local major=""
  major="$(node_major || true)"
  if [ -z "$major" ] || [ "$major" -lt "$CODEX_MIN_NODE_MAJOR" ]; then
    install_modern_node
  fi

  if command -v npm >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "npm not found, and apt-get is unavailable. Install npm first." >&2
    exit 1
  fi

  local sudo_cmd=()
  if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
      echo "sudo not found and current user is not root." >&2
      exit 1
    fi
    sudo_cmd=(sudo)
  fi
  run "${sudo_cmd[@]}" apt-get install -y --no-install-recommends npm
}

ensure_npm
existing="$(find_codex)"
if [ -n "$existing" ]; then
  echo "codex already installed: $existing"
  if [ "$DRY_RUN" -eq 0 ]; then
    codex --version || true
  fi
  ensure_path_persisted
  exit 0
fi

run mkdir -p "$CODEX_INSTALL_PREFIX"
run npm install -g --prefix "$CODEX_INSTALL_PREFIX" "$CODEX_NPM_PACKAGE"
ensure_path_now
ensure_path_persisted

if [ "$DRY_RUN" -eq 0 ]; then
  installed="$(find_codex)"
  if [ -z "$installed" ]; then
    echo "Codex CLI install finished, but codex is not on PATH." >&2
    echo "Expected: $CODEX_INSTALL_PREFIX/bin/codex" >&2
    exit 1
  fi
  echo "codex installed: $installed"
  codex --version
else
  echo "[dry-run] codex --version"
fi
