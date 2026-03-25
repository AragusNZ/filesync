#!/usr/bin/env bash
# Push local clone to master path; update row in .filesync/files.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: filesync push <local_path1> [local_path2 ...]${NC}"
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

push_one() {
  local LOCAL_PATH="$1"
  local FULL_LOCAL_PATH="$PROJECT_ROOT/$LOCAL_PATH"
  local TMP_MASTER

  if [[ ! -f "$FULL_LOCAL_PATH" ]]; then
    echo -e "${RED}Error: Local file not found: $FULL_LOCAL_PATH${NC}"
    return 1
  fi

  if ! jq -e --arg local "$LOCAL_PATH" '.files | any(.local_path == $local)' "$CONFIG_FILE" &>/dev/null; then
    echo -e "${RED}Error: '$LOCAL_PATH' is not mapped.${NC}"
    return 1
  fi

  local REPO_NAME REPO_FILE_PATH
  REPO_NAME=$(jq -r --arg local "$LOCAL_PATH" '.files[] | select(.local_path == $local) | .repo_name' "$CONFIG_FILE" | head -1)
  REPO_FILE_PATH=$(jq -r --arg local "$LOCAL_PATH" '.files[] | select(.local_path == $local) | .repo_file_path' "$CONFIG_FILE" | head -1)

  if [[ -z "$REPO_NAME" || "$REPO_NAME" == "null" ]] || [[ -z "$REPO_FILE_PATH" || "$REPO_FILE_PATH" == "null" ]]; then
    echo -e "${RED}Error: Invalid mapping for '$LOCAL_PATH'.${NC}"
    return 1
  fi

  if ! jq -e --arg n "$REPO_NAME" 'any(.name == $n)' "$FILESYNC_REPOS_FILE" &>/dev/null; then
    echo -e "${RED}Error: Repo '$REPO_NAME' not in repos.${NC}"
    return 1
  fi

  local REPO_PATH
  REPO_PATH=$(jq -r --arg n "$REPO_NAME" '.[] | select(.name == $n) | .path // ""' "$FILESYNC_REPOS_FILE" | head -1)
  if [[ -z "$REPO_PATH" || "$REPO_PATH" == "null" ]]; then
    echo -e "${RED}Error: Repo '$REPO_NAME' has no local path.${NC}"
    return 1
  fi

  local MARKER_STYLE=""
  MARKER_STYLE=$(jq -r --arg local "$LOCAL_PATH" '.files[] | select(.local_path == $local) | .marker_style // empty' "$CONFIG_FILE" | head -1)
  [[ "$MARKER_STYLE" == "null" ]] && MARKER_STYLE=""

  TMP_MASTER="$(mktemp)"
  if ! render_master_marker_file "$FULL_LOCAL_PATH" "$TMP_MASTER" "$MARKER_STYLE"; then
    rm -f "$TMP_MASTER"
    echo -e "${RED}Error: Local file must include a filesync marker.${NC}"
    return 1
  fi

  local FULL_MASTER_PATH="$PROJECT_ROOT/$REPO_PATH/$REPO_FILE_PATH"
  mkdir -p "$(dirname "$FULL_MASTER_PATH")"
  cp "$TMP_MASTER" "$FULL_MASTER_PATH"
  rm -f "$TMP_MASTER"

  filesync_write_file_row "$FILESYNC_FILES_FILE" "$PROJECT_ROOT" "$LOCAL_PATH" "$FULL_MASTER_PATH" "synced"

  echo -e "${GREEN}Pushed to master:${NC} local_path=$LOCAL_PATH repo=$REPO_NAME repo_file_path=$REPO_FILE_PATH"
}

for lp in "${LOCAL_PATHS[@]}"; do
  push_one "$lp" || filesync_die "push failed for one or more paths (see messages above)"
done
