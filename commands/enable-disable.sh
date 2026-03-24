#!/usr/bin/env bash
# Toggle file_sync_enabled in .filesync/config.json.

set -euo pipefail

_PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$_PKG/lib/resolve.sh"
filesync_resolve_or_exit

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: filesync enable | filesync disable${NC}"
  exit 1
fi

mkdir -p "$FILESYNC_DIR"
cfg="$FILESYNC_DIR/$FILESYNC_CONFIG_NAME"

if ! command -v jq &>/dev/null; then
  echo -e "${RED}jq is required.${NC}"
  exit 1
fi

if [[ ! -f "$cfg" ]]; then
  echo '{}' > "$cfg"
fi

case "$1" in
  enable)
    read -rp "Enable filesync? (y/N) " ans
    if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
      echo "Aborted."
      exit 0
    fi
    jq '.file_sync_enabled = true' "$cfg" > "${cfg}.tmp"
    mv "${cfg}.tmp" "$cfg"
    echo -e "${GREEN}filesync enabled.${NC}"
    ;;
  disable)
    jq '.file_sync_enabled = false' "$cfg" > "${cfg}.tmp"
    mv "${cfg}.tmp" "$cfg"
    echo -e "${YELLOW}filesync disabled.${NC}"
    ;;
  *)
    echo -e "${RED}Usage: filesync enable | filesync disable${NC}"
    exit 1
    ;;
esac
