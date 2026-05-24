#!/usr/bin/env bash

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Run this with source so proxy variables remain in your shell:"
  echo "  source scripts/network-turbo-on.sh"
fi

if [ ! -r /etc/network_turbo ]; then
  echo "/etc/network_turbo is not available on this machine."
  return 0 2>/dev/null || exit 0
fi

# AutoDL-specific network acceleration. Do not copy its contents into this repo.
# shellcheck disable=SC1091
source /etc/network_turbo
echo "Sourced /etc/network_turbo in the current shell."
