#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=0
CODEX_NPM_PACKAGE="${CODEX_NPM_PACKAGE:-@openai/codex}"
CODEX_INSTALL_PREFIX="${CODEX_INSTALL_PREFIX:-$HOME/.local}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/install-codex-cli.sh [--dry-run]

Install OpenAI Codex CLI after proxy setup and before the rest of the toolbox
bootstrap. The default install target is user-local: ~/.local/bin/codex.

Environment:
  CODEX_NPM_PACKAGE       default: @openai/codex
  CODEX_INSTALL_PREFIX    default: ~/.local
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

ensure_npm() {
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

  run "${sudo_cmd[@]}" apt-get update
  run "${sudo_cmd[@]}" apt-get install -y --no-install-recommends ca-certificates npm
}

existing="$(find_codex)"
if [ -n "$existing" ]; then
  echo "codex already installed: $existing"
  if [ "$DRY_RUN" -eq 0 ]; then
    codex --version || true
  fi
  ensure_path_persisted
  exit 0
fi

ensure_npm
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
