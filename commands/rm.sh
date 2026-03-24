#!/usr/bin/env bash
# Remove mapping from .filesync/files.json; strip FILE-SYNC lines from file.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: filesync rm <local_path1> [local_path2 ...]${NC}"
  exit 1
fi

declare -a LOCAL_PATHS=()
declare -A SEEN_LOCAL_PATHS=()
for arg in "$@"; do
  [[ -n "$arg" ]] || { echo -e "${RED}Error: empty local_path${NC}"; exit 1; }
  [[ -z "${SEEN_LOCAL_PATHS[$arg]:-}" ]] || { echo -e "${RED}Error: duplicate '$arg'${NC}"; exit 1; }
  SEEN_LOCAL_PATHS["$arg"]=1
  LOCAL_PATHS+=("$arg")
done

remove_one() {
  local local_path="$1"
  local full="$PROJECT_ROOT/$local_path"

  if ! jq -e --arg local "$local_path" 'any(.local_path == $local)' "$FILESYNC_FILES_FILE" &>/dev/null; then
    echo -e "${RED}Error: No mapping for '$local_path'.${NC}"
    return 1
  fi

  jq --arg local "$local_path" 'map(select(.local_path != $local))' "$FILESYNC_FILES_FILE" > "${FILESYNC_FILES_FILE}.tmp"
  mv "${FILESYNC_FILES_FILE}.tmp" "$FILESYNC_FILES_FILE"
  echo -e "${GREEN}Removed mapping:${NC} local_path=$local_path"

  if [[ -f "$full" ]]; then
    local t
    t="$(mktemp)"
    strip_file_sync_marker_lines "$full" "$t"
    mv "$t" "$full"
    echo -e "${GREEN}Stripped FILE-SYNC lines:${NC} $local_path"
  fi
}

for lp in "${LOCAL_PATHS[@]}"; do
  remove_one "$lp" || exit 1
done
