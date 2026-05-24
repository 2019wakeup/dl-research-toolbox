#!/usr/bin/env bash

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Run this with source so proxy variables are removed from your shell:"
  echo "  source scripts/proxy-off.sh"
fi

unset http_proxy
unset https_proxy
unset HTTP_PROXY
unset HTTPS_PROXY
unset all_proxy
unset ALL_PROXY
unset no_proxy
unset NO_PROXY

echo "Proxy variables removed from this shell."
