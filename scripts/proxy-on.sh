#!/usr/bin/env bash

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Run this with source so proxy variables remain in your shell:"
  echo "  source scripts/proxy-on.sh"
fi

PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${PROXY_PORT:-7890}"
NO_PROXY_VALUE="${NO_PROXY_VALUE:-localhost,127.0.0.1,::1}"
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"

export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export all_proxy="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export no_proxy="$NO_PROXY_VALUE"
export NO_PROXY="$NO_PROXY_VALUE"

echo "Proxy enabled for this shell: ${PROXY_HOST}:${PROXY_PORT}"
