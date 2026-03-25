#!/usr/bin/env bash
# Toggle file_sync_enabled in .filesync/config.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init_lite "${BASH_SOURCE[0]}"

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: filesync enable | filesync disable${NC}" >&2
  exit 1
fi

mkdir -p "$FILESYNC_DIR"
cfg="$FILESYNC_DIR/$FILESYNC_CONFIG_NAME"

if [[ ! -f "$cfg" ]]; then
  echo '{}' > "$cfg"
fi

case "$1" in
  enable)
    read -rp "Enable filesync? (y/N) " ans
    if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
      echo "Aborted." >&2
      exit 0
    fi
    jq '.file_sync_enabled = true' "$cfg" > "${cfg}.tmp"
    mv "${cfg}.tmp" "$cfg"
    echo -e "${GREEN}filesync enabled.${NC}" >&2
    ;;
  disable)
    jq '.file_sync_enabled = false' "$cfg" > "${cfg}.tmp"
    mv "${cfg}.tmp" "$cfg"
    echo -e "${YELLOW}filesync disabled.${NC}" >&2
    ;;
  *)
    echo -e "${RED}Usage: filesync enable | filesync disable${NC}" >&2
    exit 1
    ;;
esac
