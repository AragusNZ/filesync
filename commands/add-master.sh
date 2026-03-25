#!/usr/bin/env bash
# CLI: filesync add-master — promote local files to master repo and add mappings (.filesync/files.json).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/files-append.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

if [[ $# -lt 2 ]]; then
  echo -e "${RED}Usage: filesync add-master <repo_name> <local_path> ... [--also=repo1,repo2]${NC}"
  exit 1
fi

TARGET_REPO="$1"
TARGET_REPOS_RAW=""
declare -a POSITIONAL=()
declare -a LOCAL_PATHS=()
declare -a TARGET_REPO_FILE_PATHS=()

shift
for arg in "$@"; do
  if [[ "$arg" == --also=* ]]; then
    TARGET_REPOS_RAW="${arg#--also=}"
  elif [[ "$arg" == --* ]]; then
    echo -e "${RED}Error: Unknown option '$arg'.${NC}"
    exit 1
  else
    POSITIONAL+=("$arg")
  fi
done

if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
  echo -e "${RED}Error: At least one local path is required.${NC}"
  exit 1
fi

for token in "${POSITIONAL[@]}"; do
  if [[ "$token" == *":"* ]]; then
    LOCAL_PATHS+=("${token%%:*}")
    TARGET_REPO_FILE_PATHS+=("${token#*:}")
  else
    LOCAL_PATHS+=("$token")
    TARGET_REPO_FILE_PATHS+=("$token")
  fi
done

declare -A SEEN_LOCAL_PATHS=()
for local_path in "${LOCAL_PATHS[@]}"; do
  if [[ -n "${SEEN_LOCAL_PATHS[$local_path]:-}" ]]; then
    echo -e "${RED}Error: Duplicate local_path '$local_path'.${NC}"
    exit 1
  fi
  SEEN_LOCAL_PATHS["$local_path"]=1
done

if ! jq -e --arg n "$TARGET_REPO" 'any(.name == $n)' "$FILESYNC_REPOS_FILE" &>/dev/null; then
  echo -e "${RED}Error: Target repo '$TARGET_REPO' is not in repos.${NC}"
  exit 1
fi

TARGET_REPO_PATH=$(jq -r --arg n "$TARGET_REPO" '.[] | select(.name == $n) | .path // ""' "$FILESYNC_REPOS_FILE" | head -1)
if [[ -z "$TARGET_REPO_PATH" || "$TARGET_REPO_PATH" == "null" ]]; then
  echo -e "${RED}Error: Target repo '$TARGET_REPO' has no local path.${NC}"
  exit 1
fi

TARGET_FS="$PROJECT_ROOT/$TARGET_REPO_PATH/.filesync"
if [[ ! -f "$TARGET_FS/$FILESYNC_FILES_NAME" || ! -f "$TARGET_FS/$FILESYNC_REPOS_NAME" ]]; then
  echo -e "${RED}Error: Target project must have .filesync/$FILESYNC_FILES_NAME and $FILESYNC_REPOS_NAME: $TARGET_FS${NC}"
  exit 1
fi

mapfile -t TARGET_REPOS < <(
  if [[ -n "$TARGET_REPOS_RAW" ]]; then
    echo "$TARGET_REPOS_RAW" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | awk '!seen[$0]++'
  fi
)

validate_can_add() {
  local files_path="$1"
  local repos_path="$2"
  local label="$3"
  local local_path="$4"
  if ! jq -e --arg n "$TARGET_REPO" 'any(.name == $n)' "$repos_path" &>/dev/null; then
    echo -e "${RED}Error: Repo '$TARGET_REPO' is not in $label repos.${NC}"
    return 1
  fi
  if jq -e --arg local "$local_path" '.[] | select(.local_path == $local)' "$files_path" &>/dev/null; then
    echo -e "${RED}Error: local_path '$local_path' already exists in $label.${NC}"
    return 1
  fi
}

for i in "${!LOCAL_PATHS[@]}"; do
  [[ -f "$PROJECT_ROOT/${LOCAL_PATHS[$i]}" ]] || { echo -e "${RED}Local file not found: ${LOCAL_PATHS[$i]}${NC}"; exit 1; }
done

for i in "${!LOCAL_PATHS[@]}"; do
  validate_can_add "$FILESYNC_FILES_FILE" "$FILESYNC_REPOS_FILE" "current" "${LOCAL_PATHS[$i]}" || filesync_die "add-master validation failed (see messages above)"
done

for extra_repo in "${TARGET_REPOS[@]}"; do
  jq -e --arg n "$extra_repo" 'any(.name == $n)' "$FILESYNC_REPOS_FILE" &>/dev/null || {
    echo -e "${RED}Error: Extra repo '$extra_repo' not in repos.${NC}"; exit 1; }
  erp=$(jq -r --arg n "$extra_repo" '.[] | select(.name == $n) | .path // ""' "$FILESYNC_REPOS_FILE" | head -1)
  [[ -n "$erp" && "$erp" != "null" ]] || { echo -e "${RED}Error: Extra repo '$extra_repo' has no path.${NC}"; exit 1; }
  efs="$PROJECT_ROOT/$erp/.filesync"
  [[ -f "$efs/$FILESYNC_FILES_NAME" && -f "$efs/$FILESYNC_REPOS_NAME" ]] || {
    echo -e "${RED}Error: Missing $efs/$FILESYNC_FILES_NAME for --also=$extra_repo${NC}"; exit 1; }
  for i in "${!LOCAL_PATHS[@]}"; do
    validate_can_add "$efs/$FILESYNC_FILES_NAME" "$efs/$FILESYNC_REPOS_NAME" "$extra_repo" "${LOCAL_PATHS[$i]}" || filesync_die "add-master validation failed (see messages above)"
  done
done

TMP_MASTER="$(mktemp)"
TMP_CLONE="$(mktemp)"
cleanup_am() {
  rm -f "$TMP_MASTER" "$TMP_CLONE" "${FILESYNC_STATE_FILE:-}"
}
trap cleanup_am EXIT

append_minimal_then_synced() {
  local files_path="$1"
  local repos_path="$2"
  local local_path="$3"
  local target_repo_file_path="$4"
  local full_target_master_path="$5"
  local label="$6"

  local new_entry
  new_entry=$(jq -n \
    --arg repo "$TARGET_REPO" \
    --arg repo_path "$target_repo_file_path" \
    --arg local "$local_path" \
    '{repo_name: $repo, repo_file_path: $repo_path, local_path: $local}')
  filesync_files_append_entry "$files_path" "$repos_path" "$TARGET_REPO" "$new_entry" || return 1
  filesync_write_file_row "$files_path" "$PROJECT_ROOT" "$local_path" "$full_target_master_path" "synced"
  echo -e "${GREEN}Added mapping ($label):${NC} repo=$TARGET_REPO local_path=$local_path"
}

for i in "${!LOCAL_PATHS[@]}"; do
  local_path="${LOCAL_PATHS[$i]}"
  target_repo_file_path="${TARGET_REPO_FILE_PATHS[$i]}"
  full_local_path="$PROJECT_ROOT/$local_path"

  if ! render_master_marker_file "$full_local_path" "$TMP_MASTER"; then
    echo -e "${RED}Error: Local file must include a filesync marker.${NC}"
    exit 1
  fi
  if ! has_master_file_sync_marker "$TMP_MASTER"; then
    echo -e "${RED}Error: Could not produce kind=master marker.${NC}"
    exit 1
  fi

  full_target_master_path="$PROJECT_ROOT/$TARGET_REPO_PATH/$target_repo_file_path"
  mkdir -p "$(dirname "$full_target_master_path")"
  cp "$TMP_MASTER" "$full_target_master_path"
  echo -e "${GREEN}Promoted to master:${NC} $target_repo_file_path"

  if ! render_clone_from_master_file "$TMP_MASTER" "$target_repo_file_path" "$TARGET_REPO" "$TMP_CLONE"; then
    filesync_die "${local_path}: could not render clone preview from promoted master (unexpected; report a bug if this persists)"
  fi
  cp "$TMP_CLONE" "$full_local_path"
  echo -e "${GREEN}Updated local clone:${NC} $local_path"

  append_minimal_then_synced "$FILESYNC_FILES_FILE" "$FILESYNC_REPOS_FILE" "$local_path" "$target_repo_file_path" "$full_target_master_path" "current" || filesync_die "add-master failed (see messages above)"

  for extra_repo in "${TARGET_REPOS[@]}"; do
    erp=$(jq -r --arg n "$extra_repo" '.[] | select(.name == $n) | .path // ""' "$FILESYNC_REPOS_FILE" | head -1)
    efs="$PROJECT_ROOT/$erp/.filesync"
    append_minimal_then_synced "$efs/$FILESYNC_FILES_NAME" "$efs/$FILESYNC_REPOS_NAME" "$local_path" "$target_repo_file_path" \
      "$PROJECT_ROOT/$erp/$target_repo_file_path" "$extra_repo" || filesync_die "add-master failed (see messages above)"
  done
done

for extra_repo in "${TARGET_REPOS[@]}"; do
  echo -e "${YELLOW}Note:${NC} also updated $extra_repo .filesync/$FILESYNC_FILES_NAME (master file may not exist there until you copy or sync)."
done
