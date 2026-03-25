#!/usr/bin/env bash
# CLI: filesync path-mode — show or set path_mode in .filesync/config.json (relative | absolute).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync path-mode [relative|absolute]

Show or set path_mode in merged .filesync/config.json. Values: relative (default) or absolute.
When setting, updates the project config file (creating a minimal config if needed).
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init_lite "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/config-merge.sh"

MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync path-mode [relative|absolute]" >&2
      exit 1
      ;;
    *)
      if [[ -n "$MODE" ]]; then
        echo -e "${RED}Unexpected argument: $1${NC}" >&2
        exit 1
      fi
      MODE="$1"
      shift
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  filesync_merged_top_level_config | jq -r '.path_mode // "relative"'
  exit 0
fi

MODE_LC="${MODE,,}"
if [[ "$MODE_LC" != "relative" && "$MODE_LC" != "absolute" ]]; then
  echo -e "${RED}Error: path_mode must be relative or absolute (got: $MODE)${NC}" >&2
  exit 1
fi

cfg="${FILESYNC_DIR}/${FILESYNC_CONFIG_NAME}"
if [[ ! -f "$cfg" ]]; then
  echo '{}' >"$cfg"
fi

jq --arg m "$MODE_LC" '.path_mode = $m' "$cfg" >"${cfg}.tmp"
mv "${cfg}.tmp" "$cfg"
echo -e "${GREEN}path_mode set to ${MODE_LC}.${NC}" >&2
