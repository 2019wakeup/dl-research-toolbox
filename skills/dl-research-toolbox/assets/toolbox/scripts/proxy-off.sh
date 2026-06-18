#!/usr/bin/env bash

_DL_PROXY_SOURCED=0
if [ -n "${BASH_VERSION:-}" ]; then
  [ "${BASH_SOURCE:-}" != "$0" ] && _DL_PROXY_SOURCED=1
elif [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _DL_PROXY_SOURCED=1 ;; esac
else
  case "$0" in *proxy-off.sh) _DL_PROXY_SOURCED=0 ;; *) _DL_PROXY_SOURCED=1 ;; esac
fi

if [ "$_DL_PROXY_SOURCED" -eq 0 ]; then
  echo "Run this with source so proxy variables are removed from your shell:"
  echo "  source scripts/proxy-off.sh"
fi
unset _DL_PROXY_SOURCED

unset http_proxy
unset https_proxy
unset HTTP_PROXY
unset HTTPS_PROXY
unset all_proxy
unset ALL_PROXY
unset no_proxy
unset NO_PROXY

echo "Proxy variables removed from this shell."
