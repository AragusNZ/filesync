#!/usr/bin/env bash
# Push local clone to master path; update row in .filesync/files.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync push [--all] [<local_path> ...]

Copy local content to linked master paths in the repo checkout and update .filesync/files.json.

  --all              Push every clone mapping in the project (otherwise list explicit paths)

Either --all or at least one local_path is required.
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"

trap 'filesync_progress_end || true; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

PUSH_ALL=false
declare -a POSITIONAL_PATHS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --all)
      PUSH_ALL=true
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync push [--all] [<local_path1> [local_path2 ...]]" >&2
      exit 1
      ;;
    *)
      POSITIONAL_PATHS+=("$1")
      shift
      ;;
  esac
done

if [[ "$PUSH_ALL" != true ]] && [[ ${#POSITIONAL_PATHS[@]} -eq 0 ]]; then
  echo -e "${RED}Usage: filesync push [--all] [<local_path1> [local_path2 ...]]${NC}" >&2
  exit 1
fi

declare -a LOCAL_PATHS=()
declare -A SEEN_LOCAL_PATHS=()

for arg in "${POSITIONAL_PATHS[@]}"; do
  [[ -n "$arg" ]] || { echo -e "${RED}Error: empty local_path${NC}" >&2; exit 1; }
  [[ -z "${SEEN_LOCAL_PATHS[$arg]:-}" ]] || { echo -e "${RED}Error: duplicate '$arg'${NC}" >&2; exit 1; }
  SEEN_LOCAL_PATHS["$arg"]=1
  LOCAL_PATHS+=("$arg")
done

if [[ "$PUSH_ALL" == true ]]; then
  while IFS= read -r _lp; do
    [[ -z "$_lp" || "$_lp" == "null" ]] && continue
    if [[ -z "${SEEN_LOCAL_PATHS[$_lp]:-}" ]]; then
      SEEN_LOCAL_PATHS["$_lp"]=1
      LOCAL_PATHS+=("$_lp")
    fi
  done < <(jq -r '.files[] | select(.sync_status == "local_newer" and (.local_path | type == "string") and (.local_path | length > 0)) | .local_path' "$CONFIG_FILE")
fi

if [[ ${#LOCAL_PATHS[@]} -eq 0 ]]; then
  echo "filesync push: no local_newer rows to push." >&2
  exit 0
fi

_ppaths=${#LOCAL_PATHS[@]}
if filesync_progress_want "$_ppaths"; then
  filesync_progress_begin "$_ppaths"
fi
_ppi=0

push_one() {
  local LOCAL_PATH="$1"
  local FULL_LOCAL_PATH="$PROJECT_ROOT/$LOCAL_PATH"
  local TMP_MASTER

  if [[ ! -f "$FULL_LOCAL_PATH" ]]; then
    echo -e "${RED}Error: Local file not found: $FULL_LOCAL_PATH${NC}" >&2
    return 1
  fi

  if ! jq -e --arg local "$LOCAL_PATH" '.files | any(.local_path == $local)' "$CONFIG_FILE" &>/dev/null; then
    echo -e "${RED}Error: '$LOCAL_PATH' is not mapped.${NC}" >&2
    return 1
  fi

  local REPO_NAME REPO_FILE_PATH
  REPO_NAME=$(jq -r --arg local "$LOCAL_PATH" '.files[] | select(.local_path == $local) | .repo_name' "$CONFIG_FILE" | head -1)
  REPO_FILE_PATH=$(jq -r --arg local "$LOCAL_PATH" '.files[] | select(.local_path == $local) | .repo_file_path' "$CONFIG_FILE" | head -1)

  if [[ -z "$REPO_NAME" || "$REPO_NAME" == "null" ]] || [[ -z "$REPO_FILE_PATH" || "$REPO_FILE_PATH" == "null" ]]; then
    echo -e "${RED}Error: Invalid mapping for '$LOCAL_PATH'.${NC}" >&2
    return 1
  fi

  if ! jq -e --arg n "$REPO_NAME" 'any(.name == $n)' "$FILESYNC_REPOS_FILE" &>/dev/null; then
    echo -e "${RED}Error: Repo '$REPO_NAME' not in repos.${NC}" >&2
    return 1
  fi

  local REPO_DIR
  REPO_DIR="$(filesync_project_resolve_repo_dir "$PROJECT_ROOT" "$REPO_NAME")"
  if [[ -z "$REPO_DIR" ]]; then
    echo -e "${RED}Error: Repo '$REPO_NAME' has no resolvable local path.${NC}" >&2
    return 1
  fi

  local MARKER_STYLE=""
  MARKER_STYLE=$(jq -r --arg local "$LOCAL_PATH" '.files[] | select(.local_path == $local) | .marker_style // empty' "$CONFIG_FILE" | head -1)
  [[ "$MARKER_STYLE" == "null" ]] && MARKER_STYLE=""

  TMP_MASTER="$(mktemp)"
  if ! render_master_marker_file "$FULL_LOCAL_PATH" "$TMP_MASTER" "$MARKER_STYLE"; then
    rm -f "$TMP_MASTER"
    echo -e "${RED}Error: Local file must include a filesync marker.${NC}" >&2
    return 1
  fi

  local FULL_MASTER_PATH="$REPO_DIR/$REPO_FILE_PATH"
  mkdir -p "$(dirname "$FULL_MASTER_PATH")"
  cp "$TMP_MASTER" "$FULL_MASTER_PATH"
  rm -f "$TMP_MASTER"

  filesync_write_file_row "$FILESYNC_FILES_FILE" "$PROJECT_ROOT" "$LOCAL_PATH" "$FULL_MASTER_PATH" "synced"

  echo -e "${GREEN}Pushed to master:${NC} local_path=$LOCAL_PATH repo=$REPO_NAME repo_file_path=$REPO_FILE_PATH" >&2
}

for lp in "${LOCAL_PATHS[@]}"; do
  push_one "$lp" || filesync_die "push failed for one or more paths (see messages above)"
  _ppi=$((_ppi + 1))
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    filesync_progress_update "$_ppi"
  fi
done

filesync_progress_end
