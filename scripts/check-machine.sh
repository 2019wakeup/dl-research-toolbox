#!/usr/bin/env bash
set -Eeuo pipefail

TOOLS=(
  git
  git-lfs
  tmux
  curl
  wget
  aria2c
  jq
  rg
  fzf
  htop
  lsof
  rsync
  ssh
  nvidia-smi
  nvcc
  nvitop
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
