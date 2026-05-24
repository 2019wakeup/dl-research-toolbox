#!/usr/bin/env bash
set -Eeuo pipefail

SESSION="${1:-research}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux not found. Run scripts/bootstrap.sh first." >&2
  exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach-session -t "$SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION" -n shell
tmux new-window -t "$SESSION" -n monitor
tmux send-keys -t "$SESSION:monitor" 'watch -n 2 nvidia-smi' C-m
tmux new-window -t "$SESSION" -n logs
tmux select-window -t "$SESSION:shell"
tmux attach-session -t "$SESSION"
