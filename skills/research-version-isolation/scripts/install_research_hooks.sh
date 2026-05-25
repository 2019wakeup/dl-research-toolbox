#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"
if [ ! -d "$ROOT/.git" ]; then
  echo "Not a Git repository root: $ROOT" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$ROOT/.git/hooks"
GUARD_TARGET="$HOOK_DIR/research_memory_guard.py"
HOOK_TARGET="$HOOK_DIR/pre-commit"
PREVIOUS_HOOK="$HOOK_DIR/pre-commit.before-research-guard"

mkdir -p "$HOOK_DIR"
cp "$SCRIPT_DIR/research_memory_guard.py" "$GUARD_TARGET"
chmod +x "$GUARD_TARGET"

if [ -f "$HOOK_TARGET" ] && ! grep -q 'research_memory_guard.py' "$HOOK_TARGET"; then
  if [ ! -f "$PREVIOUS_HOOK" ]; then
    cp "$HOOK_TARGET" "$PREVIOUS_HOOK"
    chmod +x "$PREVIOUS_HOOK"
    echo "Existing pre-commit hook preserved as: $PREVIOUS_HOOK"
  else
    echo "Existing preserved hook kept: $PREVIOUS_HOOK"
  fi
fi

cat > "$HOOK_TARGET" <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(git rev-parse --show-toplevel)"
HOOK_DIR="$ROOT/.git/hooks"
python3 "$HOOK_DIR/research_memory_guard.py" --root "$ROOT" --staged
if [ -x "$HOOK_DIR/pre-commit.before-research-guard" ]; then
  "$HOOK_DIR/pre-commit.before-research-guard"
fi
HOOK
chmod +x "$HOOK_TARGET"

python3 "$GUARD_TARGET" --root "$ROOT" --init-root --rebuild-experiment-index

echo "Installed research memory pre-commit guard for: $ROOT"
