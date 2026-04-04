#!/usr/bin/env bash
# Push local clone to master path; update row in .filesync/files.json.
# Optional: push --to-clones copies canonical master into every tracked clone (multi-project).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync push [--all] [<local_path> ...] | filesync push --to-clones <path> [--dry-run]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}

Copy your edited files to their source paths in the repo checkout and update .filesync/files.json.

  --all              Push every clone mapping in this project (otherwise name each path)

  --to-clones <path> After you edit the source copy (any path that resolves to the master), push that
                      content into every linked clone across all projects that track it (runs
                      filesync sync in each project—the opposite of the usual push direction).
  --dry-run           With --to-clones only: show sync actions without overwriting clones (check still runs first)

Normal push: either --all or at least one local path.
Do not combine --to-clones with --all or extra paths.
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/file-related-mappings.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"

trap 'filesync_progress_end || true; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

PUSH_ALL=false
PUSH_TO_CLONES=false
TO_CLONES_PATH=""
TO_CLONES_DRY_RUN=false
declare -a POSITIONAL_PATHS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --all)
      PUSH_ALL=true
      shift
      ;;
    --to-clones)
      PUSH_TO_CLONES=true
      shift
      if [[ $# -lt 1 ]]; then
        filesync_usage_error_stderr "Usage: filesync push --to-clones <path> [--dry-run]"
        exit 1
      fi
      TO_CLONES_PATH="$1"
      shift
      ;;
    --dry-run)
      TO_CLONES_DRY_RUN=true
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      POSITIONAL_PATHS+=("$1")
      shift
      ;;
  esac
done

if [[ "$PUSH_TO_CLONES" == true ]]; then
  if [[ "$PUSH_ALL" == true ]] || [[ ${#POSITIONAL_PATHS[@]} -gt 0 ]]; then
    echo -e "${RED}Cannot combine --to-clones with --all or extra paths.${NC}" >&2
    filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
    exit 1
  fi
else
  if [[ "$TO_CLONES_DRY_RUN" == true ]]; then
    echo -e "${RED}--dry-run is only valid with push --to-clones.${NC}" >&2
    filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
    exit 1
  fi
fi

if [[ "$PUSH_TO_CLONES" == true ]]; then
  if ! filesync_file_rel_gather_from_path "$TO_CLONES_PATH"; then
    exit 1
  fi
  if [[ ${#FILESYNC_RELATED_LINES[@]} -eq 0 ]]; then
    echo "filesync push --to-clones: no related clone rows." >&2
    exit 0
  fi

  FS_BIN="$FILESYNC_PKG_ROOT/bin/filesync"
  AGG_RC=0

  for proot in "${!FILESYNC_REL_ROOT_TO_LOCALS[@]}"; do
    [[ -z "${FILESYNC_REL_ROOT_TO_LOCALS[$proot]:-}" ]] && continue
    mapfile -t _locs <<<"${FILESYNC_REL_ROOT_TO_LOCALS[$proot]}"
    # -c/--check refreshes status; --status=all allows rows still marked synced to be diffed and updated.
    sync_args=(sync -c --repo="$FILESYNC_REL_RNAME" -f --status=all)
    [[ "$TO_CLONES_DRY_RUN" == true ]] && sync_args+=(--dry-run)
    _n_el=0
    for _loc in "${_locs[@]}"; do
      [[ -z "${_loc// }" ]] && continue
      sync_args+=(--file="$_loc")
      _n_el=$((_n_el + 1))
    done
    [[ "$_n_el" -eq 0 ]] && continue
    set +e
    # Do not inherit project pins from the invoking project (FILESYNC_DIR/CONFIG_FILE/…);
    # nested sync must discover .filesync from $proot via cwd alone.
    (cd "$proot" && env -u FILESYNC_DIR -u FILESYNC_PROJECT_ROOT -u CONFIG_FILE -u FILESYNC_STATE_FILE -u PROJECT_ROOT \
      "$FS_BIN" "${sync_args[@]}")
    r=$?
    set -e
    if [[ "$r" -ne 0 ]]; then
      AGG_RC="$r"
    fi
  done

  filesync_progress_end
  exit "${AGG_RC:-0}"
fi

if [[ "$PUSH_ALL" != true ]] && [[ ${#POSITIONAL_PATHS[@]} -eq 0 ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
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
  REPO_DIR="$(filesync_project_resolve_repo_dir "$REPO_PATH_ROOT" "$FILESYNC_REPOS_FILE" "$REPO_NAME")"
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
