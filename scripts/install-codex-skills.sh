#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/skills"
DEST="${CODEX_HOME:-$HOME/.codex}/skills"
DRY_RUN=0
LIST_ONLY=0
SELECTED=()

usage() {
  cat <<USAGE
Usage: bash scripts/install-codex-skills.sh [options]

Install bundled Codex skills from this repository into ~/.codex/skills.

Options:
  --dest PATH       Install destination. Default: \${CODEX_HOME:-\$HOME/.codex}/skills
  --skill NAME      Install only one skill. Can be repeated.
  --list            List bundled skills and exit.
  --dry-run         Show what would be copied.
  -h, --help        Show this help.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)
      DEST="${2:?missing value for --dest}"
      shift 2
      ;;
    --skill)
      SELECTED+=("${2:?missing value for --skill}")
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
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

if [ ! -d "$SRC" ]; then
  echo "No bundled skills directory found: $SRC" >&2
  exit 1
fi

ALL_SKILLS=()
for dir in "$SRC"/*; do
  [ -d "$dir" ] || continue
  [ -f "$dir/SKILL.md" ] || continue
  ALL_SKILLS+=("$(basename "$dir")")
done

if [ ${#SELECTED[@]} -eq 0 ]; then
  SKILLS=("${ALL_SKILLS[@]}")
else
  SKILLS=("${SELECTED[@]}")
fi

if [ ${#SKILLS[@]} -eq 0 ]; then
  echo "No installable skills found under: $SRC" >&2
  exit 1
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  printf "%s\n" "${ALL_SKILLS[@]}"
  exit 0
fi

copy_skill() {
  local name="$1"
  local source="$SRC/$name"
  local target="$DEST/$name"

  if [ ! -f "$source/SKILL.md" ]; then
    echo "Missing bundled skill: $name" >&2
    return 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "Would install $name -> $target"
    return 0
  fi

  mkdir -p "$target"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude __pycache__ --exclude "*.pyc" "$source/" "$target/"
  else
    (cd "$source" && find . \
      -type d -name __pycache__ -prune -o \
      -type f ! -name "*.pyc" -print0) | while IFS= read -r -d "" file; do
      mkdir -p "$target/$(dirname "$file")"
      cp -p "$source/$file" "$target/$file"
    done
  fi
  echo "Installed $name -> $target"
}

mkdir -p "$DEST"
for skill in "${SKILLS[@]}"; do
  copy_skill "$skill"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "Planned ${#SKILLS[@]} skill(s)."
else
  cat <<EOF

Installed ${#SKILLS[@]} skill(s).
Restart Codex sessions that should pick up newly installed or updated skills.
EOF
fi
