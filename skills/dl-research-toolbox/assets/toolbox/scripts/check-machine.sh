#!/usr/bin/env bash
set -Eeuo pipefail

TOOLS=(
  gh
  git
  git-lfs
  npm
  uv
  tmux
  curl
  wget
  aria2c
  jq
  rg
  fzf
  ruff
  pytest
  htop
  lsof
  rsync
  ssh
  nvidia-smi
  nvcc
  nvitop
  gdown
  huggingface-cli
  tensorboard
  mihomo
)

echo "Tool check"
echo "----------"
for tool in "${TOOLS[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '[ok]   %-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '[miss] %-12s\n' "$tool"
  fi
done


echo
echo "Python tools venv"
echo "-----------------"
PYTHON_TOOLS_VENV="${PYTHON_TOOLS_VENV:-$HOME/.local/venvs/research-tools}"
if [ -x "$PYTHON_TOOLS_VENV/bin/python" ]; then
  echo "venv: $PYTHON_TOOLS_VENV"
  "$PYTHON_TOOLS_VENV/bin/python" - <<'PY'
import importlib.util
mods = [
    "numpy", "pandas", "scipy", "sklearn", "matplotlib", "tqdm",
    "rich", "yaml", "PIL", "cv2", "h5py", "einops", "tensorboard",
    "huggingface_hub", "datasets", "gdown", "nvitop", "pytest", "ruff",
    "ipykernel",
]
for mod in mods:
    print(f"[{'ok' if importlib.util.find_spec(mod) else 'miss'}] {mod}")
PY
else
  echo "venv missing: $PYTHON_TOOLS_VENV"
fi

echo
echo "GPU check"
echo "---------"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader || true
else
  echo "nvidia-smi not found"
fi

echo
echo "Proxy env"
echo "---------"
for name in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; do
  if [ -n "${!name:-}" ]; then
    echo "$name is set"
  else
    echo "$name is unset"
  fi
done

echo
echo "Network check"
echo "-------------"
if command -v curl >/dev/null 2>&1; then
  for url in https://github.com https://huggingface.co https://pypi.org; do
    if curl -I -L --max-time 8 "$url" >/dev/null 2>&1; then
      echo "[ok]   $url"
    else
      echo "[fail] $url"
    fi
  done
else
  echo "curl not found"
fi

echo
echo "AutoDL network_turbo"
echo "--------------------"
if [ -r /etc/network_turbo ]; then
  echo "/etc/network_turbo is available"
else
  echo "/etc/network_turbo is unavailable"
fi
