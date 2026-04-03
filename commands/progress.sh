#!/usr/bin/env bash
# Set or show progress_display in system preferences: hidden | bar | percent (default: percent).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync progress [hidden|bar|percent]

Show or set progress_display in the system preferences file for long TTY loops (default: percent).

  hidden   Disable progress output
  bar      Full bar on stderr (TTY, many items)
  percent  Compact [NNN%] on stderr (TTY, many items)

With no argument, prints the current effective value (merged with package defaults).
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/preferences-merge.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

prefs="${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"
mkdir -p "$(dirname "$prefs")"
if [[ ! -f "$prefs" ]]; then
  printf '%s\n' '{}' | jq . >"$prefs"
fi

mode="${1:-}"
if [[ -z "$mode" ]]; then
  filesync_merged_preferences | jq -r '.progress_display // "percent"'
  exit 0
fi

case "$mode" in
  hidden | bar | percent)
    jq --arg m "$mode" '.progress_display = $m' "$prefs" >"${prefs}.tmp"
    mv "${prefs}.tmp" "$prefs"
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
