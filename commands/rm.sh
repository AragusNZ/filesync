#!/usr/bin/env bash
# Remove mapping from .filesync/files.json; strip clone/detached marker from local file (keep kind=master).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"

trap 'filesync_progress_end || true; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: filesync rm|remove <local_path1> [local_path2 ...]${NC}" >&2
  exit 1
fi

declare -a LOCAL_PATHS=()
declare -A SEEN_LOCAL_PATHS=()
for arg in "$@"; do
  [[ -n "$arg" ]] || { echo -e "${RED}Error: empty local_path${NC}" >&2; exit 1; }
  [[ -z "${SEEN_LOCAL_PATHS[$arg]:-}" ]] || { echo -e "${RED}Error: duplicate '$arg'${NC}" >&2; exit 1; }
  SEEN_LOCAL_PATHS["$arg"]=1
  LOCAL_PATHS+=("$arg")
done

_rpaths=${#LOCAL_PATHS[@]}
if filesync_progress_want "$_rpaths"; then
  filesync_progress_begin "$_rpaths"
fi
_rpi=0

remove_one() {
  local local_path="$1"
  local full="$PROJECT_ROOT/$local_path"

  if ! jq -e --arg local "$local_path" 'any(.local_path == $local)' "$FILESYNC_FILES_FILE" &>/dev/null; then
    echo -e "${RED}Error: No mapping for '$local_path'.${NC}" >&2
    return 1
  fi

  jq --arg local "$local_path" 'map(select(.local_path != $local))' "$FILESYNC_FILES_FILE" > "${FILESYNC_FILES_FILE}.tmp"
  mv "${FILESYNC_FILES_FILE}.tmp" "$FILESYNC_FILES_FILE"
  echo -e "${GREEN}Removed mapping:${NC} local_path=$local_path" >&2

  if [[ -f "$full" ]]; then
    local t
    t="$(mktemp)"
    strip_non_master_filesync_marker_lines "$full" "$t"
    mv "$t" "$full"
    echo -e "${GREEN}Removed local filesync marker (left kind=master if present):${NC} $local_path" >&2
  fi
}

for lp in "${LOCAL_PATHS[@]}"; do
  remove_one "$lp" || filesync_die "remove failed for one or more paths (see messages above)"
  _rpi=$((_rpi + 1))
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    filesync_progress_update "$_rpi"
  fi
done

filesync_progress_end
