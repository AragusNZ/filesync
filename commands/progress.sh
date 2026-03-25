#!/usr/bin/env bash
# Set or show progress_display in .filesync/config.json: hidden | bar | percent (default: percent).
# Dispatched as: filesync progress [hidden|bar|percent]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/config-merge.sh"
filesync_command_init_lite "${BASH_SOURCE[0]}"

mkdir -p "$FILESYNC_DIR"
cfg="$FILESYNC_DIR/$FILESYNC_CONFIG_NAME"
if [[ ! -f "$cfg" ]]; then
  echo '{}' >"$cfg"
fi

mode="${1:-}"
if [[ -z "$mode" ]]; then
  filesync_merged_top_level_config | jq -r '.progress_display // "percent"'
  exit 0
fi

case "$mode" in
  hidden | bar | percent)
    jq --arg m "$mode" '.progress_display = $m | del(.show_progress)' "$cfg" >"${cfg}.tmp"
    mv "${cfg}.tmp" "$cfg"
    case "$mode" in
      hidden) echo -e "${YELLOW}Progress disabled (hidden).${NC}" >&2 ;;
      bar) echo -e "${GREEN}Progress style: full bar on stderr (TTY, 10+ items).${NC}" >&2 ;;
      percent) echo -e "${GREEN}Progress style: compact [NNN%] on stderr (TTY, 10+ items).${NC}" >&2 ;;
    esac
    ;;
  *)
    echo -e "${RED}Usage: filesync progress [hidden|bar|percent]${NC}" >&2
    exit 1
    ;;
esac
