#!/usr/bin/env bash
# Repair broken mappings: unmap, delete local file + unmap, or recreate local from master.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync handle-missing <local_path> (--unmap | --delete-local-and-unmap | --recreate-from-master)'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}

Fix a broken mapping when the local file or its source is missing. Run from a project directory
(filesync discovers .filesync/ upward). The row is selected by local_path.

Arguments:

  <local_path>    Tracked path in this project.

Choose exactly one action:

  --unmap
    Stop tracking: remove the row and clear clone markers on disk when present.

  --delete-local-and-unmap
    Delete the local file, then stop tracking (row removal same as --unmap).

  --recreate-from-master
    Copy from the source file in the repo checkout into the local path (source must exist).
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/rm-mapping.sh"
filesync_command_init "${BASH_SOURCE[0]}"

declare -a FILESYNC_CLONED_TEMP_DIRS=()
cleanup_hm() {
  rm -f "${FILESYNC_STATE_FILE:-}"
  rm -rf "${FILESYNC_CLONED_TEMP_DIRS[@]:-}"
}
trap cleanup_hm EXIT

LOCAL_PATH=""
DO_UNMAP=false
DO_DEL=false
DO_REC=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unmap)
      DO_UNMAP=true
      shift
      ;;
    --delete-local-and-unmap)
      DO_DEL=true
      shift
      ;;
    --recreate-from-master)
      DO_REC=true
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      [[ -n "$1" ]] || { echo -e "${RED}local_path cannot be empty${NC}" >&2; exit 1; }
      [[ -z "$LOCAL_PATH" ]] || { echo -e "${RED}Only one local_path is allowed${NC}" >&2; exit 1; }
      LOCAL_PATH="$1"
      shift
      ;;
  esac
done

[[ -n "$LOCAL_PATH" ]] || {
  echo -e "${RED}<local_path> is required${NC}" >&2
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
}

acts=0
$DO_UNMAP && acts=$((acts + 1))
$DO_DEL && acts=$((acts + 1))
$DO_REC && acts=$((acts + 1))
[[ "$acts" -eq 1 ]] || { echo -e "${RED}Specify exactly one of --unmap, --delete-local-and-unmap, --recreate-from-master${NC}" >&2; exit 1; }

if ! jq -e --arg l "$LOCAL_PATH" 'any(.local_path == $l)' "$FILESYNC_FILES_FILE" &>/dev/null; then
  echo -e "${RED}No files.json row with local_path='$LOCAL_PATH'.${NC}" >&2
  exit 1
fi

if $DO_UNMAP; then
  filesync_remove_file_mapping_row "$PROJECT_ROOT" "$FILESYNC_FILES_FILE" "$LOCAL_PATH"
  exit 0
fi

if $DO_DEL; then
  full="$PROJECT_ROOT/$LOCAL_PATH"
  [[ -e "$full" ]] && rm -f "$full"
  filesync_remove_file_mapping_row "$PROJECT_ROOT" "$FILESYNC_FILES_FILE" "$LOCAL_PATH"
  exit 0
fi

# recreate-from-master
REPO_ID=$(jq -r --arg l "$LOCAL_PATH" 'first(.[] | select(.local_path == $l) | .repo_id) // empty' "$FILESYNC_FILES_FILE")
REPO_FILE_PATH=$(jq -r --arg l "$LOCAL_PATH" 'first(.[] | select(.local_path == $l) | .repo_file_path) // empty' "$FILESYNC_FILES_FILE")
[[ -n "$REPO_ID" && "$REPO_ID" != "null" && -n "$REPO_FILE_PATH" ]] || { echo -e "${RED}Invalid row for local_path (need repo_id; run: filesync migrate)${NC}" >&2; exit 1; }
REPO_NAME="$(filesync_repo_name_from_id "$FILESYNC_REPOS_FILE" "$REPO_ID")"
[[ -n "$REPO_NAME" ]] || { echo -e "${RED}Unknown repo_id in row for local_path${NC}" >&2; exit 1; }

REPO_ROOT=$(filesync_get_repo_dir "$REPO_NAME") || exit 1
FULL_MASTER="$REPO_ROOT/$REPO_FILE_PATH"
[[ -f "$FULL_MASTER" ]] || { echo -e "${RED}Master file missing in repo: $REPO_FILE_PATH${NC}" >&2; exit 1; }

full_local="$PROJECT_ROOT/$LOCAL_PATH"
mkdir -p "$(dirname "$full_local")"
tmp="$(mktemp)"
if ! render_clone_from_master_file "$FULL_MASTER" "$REPO_FILE_PATH" "$REPO_NAME" "$tmp" "$REPO_ID"; then
  rm -f "$tmp"
  exit 1
fi
mv "$tmp" "$full_local"
echo -e "${GREEN}Recreated local file from master:${NC} $LOCAL_PATH" >&2
