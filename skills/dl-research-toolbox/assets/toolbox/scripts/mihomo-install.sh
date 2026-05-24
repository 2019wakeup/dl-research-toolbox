#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${MIHOMO_REPO:-MetaCubeX/mihomo}"
INSTALL_ROOT="${MIHOMO_HOME:-$HOME/.local/opt/mihomo}"
BIN_DIR="${MIHOMO_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${MIHOMO_CONFIG_DIR:-$HOME/.config/mihomo}"
STATE_DIR="${MIHOMO_STATE_DIR:-$HOME/.local/state/mihomo}"
USE_NETWORK_TURBO="${USE_NETWORK_TURBO:-auto}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

case "$(uname -m)" in
  x86_64|amd64) ASSET_ARCH="amd64" ;;
  aarch64|arm64) ASSET_ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

case "$(uname -s)" in
  Linux) ASSET_OS="linux" ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

maybe_enable_network_turbo() {
  case "$USE_NETWORK_TURBO" in
    1|true|yes|auto)
      if [ -r /etc/network_turbo ]; then
        # shellcheck disable=SC1091
        source /etc/network_turbo
        echo "Enabled /etc/network_turbo for mihomo download."
      elif [ "$USE_NETWORK_TURBO" != "auto" ]; then
        echo "USE_NETWORK_TURBO requested, but /etc/network_turbo is unavailable." >&2
      fi
      ;;
    0|false|no) ;;
    *)
      echo "Invalid USE_NETWORK_TURBO=$USE_NETWORK_TURBO" >&2
      exit 2
      ;;
  esac
}

release_json() {
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest"
}

select_download_url() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r \
      --arg os "$ASSET_OS" \
      --arg arch "$ASSET_ARCH" \
      '.assets[].browser_download_url
       | select(test($os + "-" + $arch))
       | select(test("\\.gz$"))
       | select((test("compatible") | not))' <<<"$json" | head -n 1
  else
    grep -Eo 'https://[^"]+' <<<"$json" \
      | grep "${ASSET_OS}-${ASSET_ARCH}" \
      | grep '\.gz$' \
      | grep -v compatible \
      | head -n 1
  fi
}

maybe_enable_network_turbo

echo "Resolving latest ${REPO} release for ${ASSET_OS}-${ASSET_ARCH}..."
JSON="$(release_json)"
DOWNLOAD_URL="$(select_download_url "$JSON")"

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
  echo "Could not find mihomo release asset for ${ASSET_OS}-${ASSET_ARCH}." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE="$TMP_DIR/mihomo.gz"
BIN_TMP="$TMP_DIR/mihomo"

echo "Downloading $DOWNLOAD_URL"
curl -fL "$DOWNLOAD_URL" -o "$ARCHIVE"
gzip -dc "$ARCHIVE" > "$BIN_TMP"
chmod +x "$BIN_TMP"

mkdir -p "$INSTALL_ROOT/bin" "$BIN_DIR" "$CONFIG_DIR" "$STATE_DIR"
cp "$BIN_TMP" "$INSTALL_ROOT/bin/mihomo"
ln -sfn "$INSTALL_ROOT/bin/mihomo" "$BIN_DIR/mihomo"

if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
  cp "$REPO_ROOT/network/mihomo/config.yaml.example" "$CONFIG_DIR/config.yaml"
  echo "Created empty config template: $CONFIG_DIR/config.yaml"
fi

cat <<DONE
mihomo installed:
  binary: $INSTALL_ROOT/bin/mihomo
  symlink: $BIN_DIR/mihomo
  config: $CONFIG_DIR/config.yaml
  state:  $STATE_DIR

Edit the config before relying on the proxy:
  \$EDITOR $CONFIG_DIR/config.yaml
DONE
