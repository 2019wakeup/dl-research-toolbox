#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="${TOOLBOX_BIN_DIR:-$HOME/.local/bin}"
SYSTEM_BIN_DIR="${TOOLBOX_SYSTEM_BIN_DIR:-/usr/local/bin}"
INSTALL_SYSTEM_CLI="${TOOLBOX_INSTALL_SYSTEM_CLI:-auto}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/install-toolbox-cli.sh [--dry-run]

Install the repository entrypoint as `toolbox` in ~/.local/bin.

Options:
  --dry-run     Print planned changes.
  --no-system   Do not install /usr/local/bin/toolbox even when writable.
  -h, --help    Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-system) INSTALL_SYSTEM_CLI=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ensure_profile_line() {
  local profile="$1"
  local line="$2"

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

path_line() {
  if [ "$BIN_DIR" = "$HOME/.local/bin" ]; then
    printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"'
  else
    printf 'export PATH="%s:$PATH"\n' "$BIN_DIR"
  fi
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] mkdir -p $BIN_DIR"
  echo "[dry-run] chmod +x $REPO_ROOT/toolbox"
  echo "[dry-run] ln -sfn $REPO_ROOT/toolbox $BIN_DIR/toolbox"
else
  mkdir -p "$BIN_DIR"
  chmod +x "$REPO_ROOT/toolbox"
  ln -sfn "$REPO_ROOT/toolbox" "$BIN_DIR/toolbox"
fi

install_system_cli=0
case "$INSTALL_SYSTEM_CLI" in
  1|true|yes|on) install_system_cli=1 ;;
  0|false|no|off) install_system_cli=0 ;;
  auto)
    if [ "$(id -u)" -eq 0 ] || [ -w "$SYSTEM_BIN_DIR" ]; then
      install_system_cli=1
    fi
    ;;
  *) echo "Invalid TOOLBOX_INSTALL_SYSTEM_CLI: $INSTALL_SYSTEM_CLI" >&2; exit 2 ;;
esac

if [ "$install_system_cli" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] mkdir -p $SYSTEM_BIN_DIR"
    echo "[dry-run] ln -sfn $REPO_ROOT/toolbox $SYSTEM_BIN_DIR/toolbox"
  else
    mkdir -p "$SYSTEM_BIN_DIR"
    ln -sfn "$REPO_ROOT/toolbox" "$SYSTEM_BIN_DIR/toolbox"
  fi
fi

profile_path_line="$(path_line)"
ensure_profile_line "$HOME/.bashrc" "$profile_path_line"
ensure_profile_line "$HOME/.profile" "$profile_path_line"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) export PATH="$BIN_DIR:$PATH" ;;
esac

echo "toolbox CLI installed at: $BIN_DIR/toolbox"
if [ "$install_system_cli" -eq 1 ]; then
  echo "toolbox system shim installed at: $SYSTEM_BIN_DIR/toolbox"
fi
