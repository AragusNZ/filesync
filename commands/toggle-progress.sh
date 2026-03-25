#!/usr/bin/env bash
# Set show_progress in .filesync/config.json (merged default: true).
# Dispatched as: filesync show-progress | filesync hide-progress

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init_lite "${BASH_SOURCE[0]}"

mode="${1:-}"
if [[ "$mode" != show && "$mode" != hide ]]; then
  echo -e "${RED}Usage: filesync show-progress | filesync hide-progress${NC}" >&2
  exit 1
fi

mkdir -p "$FILESYNC_DIR"
cfg="$FILESYNC_DIR/$FILESYNC_CONFIG_NAME"
if [[ ! -f "$cfg" ]]; then
  echo '{}' >"$cfg"
fi

case "$mode" in
  show)
    jq '.show_progress = true' "$cfg" >"${cfg}.tmp"
    mv "${cfg}.tmp" "$cfg"
    echo -e "${GREEN}Progress bars enabled (when stderr is a TTY and the loop has at least 10 items).${NC}" >&2
    ;;
  hide)
    jq '.show_progress = false' "$cfg" >"${cfg}.tmp"
    mv "${cfg}.tmp" "$cfg"
    echo -e "${YELLOW}Progress bars disabled.${NC}" >&2
    ;;
esac
