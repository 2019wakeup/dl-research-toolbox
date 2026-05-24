#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ASSET_DIR="$SKILL_DIR/assets/toolbox"
REPO_URL="${DL_RESEARCH_TOOLBOX_REPO:-https://github.com/2019wakeup/dl-research-toolbox.git}"
TARGET_DIR="${DL_RESEARCH_TOOLBOX_PATH:-$HOME/dl-research-toolbox}"
FROM_GIT=0
BOOTSTRAP=0
INSTALL_MIHOMO=0
IMPORT_SUBSCRIPTION=0
NETWORK_FIRST=0
REPLACE_RUNNING=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/install_toolbox.sh [options]

Materialize the DL research toolbox from this skill's bundled asset, or clone/update the GitHub repo.

Options:
  --path PATH           Target directory. Default: ~/dl-research-toolbox
  --from-git           Clone or update from DL_RESEARCH_TOOLBOX_REPO instead of bundled asset.
  --repo URL            Git repository URL for --from-git.
  --network-first      Run scripts/network-first-setup.sh after install. Recommended.
  --bootstrap          Run scripts/bootstrap.sh after install.
  --install-mihomo     Run scripts/mihomo-install.sh after install.
  --import-subscription Run scripts/mihomo-import-subscription.sh after install.
  --replace-running    Pass --replace-running to subscription import.
  -h, --help           Show this help.

Environment:
  DL_RESEARCH_TOOLBOX_REPO   Default Git repo URL.
  DL_RESEARCH_TOOLBOX_PATH   Default target directory.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --path)
      TARGET_DIR="${2:-}"
      shift 2
      ;;
    --repo)
      REPO_URL="${2:-}"
      FROM_GIT=1
      shift 2
      ;;
    --from-git)
      FROM_GIT=1
      shift
      ;;
    --network-first)
      NETWORK_FIRST=1
      shift
      ;;
    --bootstrap)
      BOOTSTRAP=1
      shift
      ;;
    --install-mihomo)
      INSTALL_MIHOMO=1
      shift
      ;;
    --import-subscription)
      IMPORT_SUBSCRIPTION=1
      shift
      ;;
    --replace-running)
      REPLACE_RUNNING=1
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

if [ -z "$TARGET_DIR" ]; then
  echo "Target directory is empty." >&2
  exit 2
fi

copy_asset() {
  if [ ! -d "$ASSET_DIR" ]; then
    echo "Missing bundled toolbox asset: $ASSET_DIR" >&2
    exit 1
  fi
  mkdir -p "$TARGET_DIR"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$ASSET_DIR/" "$TARGET_DIR/"
  else
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "$ASSET_DIR/." "$TARGET_DIR/"
  fi
}

sync_git() {
  if [ -d "$TARGET_DIR/.git" ]; then
    git -C "$TARGET_DIR" pull --ff-only
  else
    mkdir -p "$(dirname "$TARGET_DIR")"
    git clone "$REPO_URL" "$TARGET_DIR"
  fi
}

if [ "$FROM_GIT" -eq 1 ]; then
  sync_git
else
  copy_asset
fi

chmod +x "$TARGET_DIR"/scripts/*.sh

echo "Toolbox ready: $TARGET_DIR"

if [ "$NETWORK_FIRST" -eq 1 ]; then
  args=()
  if [ "$REPLACE_RUNNING" -eq 1 ]; then
    args+=(--replace-running)
  fi
  (cd "$TARGET_DIR" && bash scripts/network-first-setup.sh "${args[@]}")
  exit 0
fi

if [ "$BOOTSTRAP" -eq 1 ]; then
  (cd "$TARGET_DIR" && bash scripts/bootstrap.sh)
fi

if [ "$INSTALL_MIHOMO" -eq 1 ]; then
  (cd "$TARGET_DIR" && bash scripts/mihomo-install.sh)
fi

if [ "$IMPORT_SUBSCRIPTION" -eq 1 ]; then
  args=()
  if [ "$REPLACE_RUNNING" -eq 1 ]; then
    args+=(--replace-running)
  fi
  (cd "$TARGET_DIR" && bash scripts/mihomo-import-subscription.sh "${args[@]}")
fi
