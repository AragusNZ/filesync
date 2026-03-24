#!/usr/bin/env bash
# Add file mappings to .filesync/files.json (--also updates sibling projects' files.json).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/files-append.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ $# -lt 2 ]]; then
  echo -e "${RED}Usage: filesync add <repo_name> <repo_file_path> ... [--also=repo1,repo2]${NC}"
  exit 1
fi

REPO_NAME="$1"
TARGET_REPOS_RAW=""
declare -a POSITIONAL=()
declare -a REPO_FILE_PATHS=()
declare -a LOCAL_PATHS=()

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
  echo -e "${RED}Error: At least one repo file path is required.${NC}"
  exit 1
fi

for token in "${POSITIONAL[@]}"; do
  if [[ "$token" == *":"* ]]; then
    REPO_FILE_PATHS+=("${token%%:*}")
    LOCAL_PATHS+=("${token#*:}")
  else
    REPO_FILE_PATHS+=("$token")
    LOCAL_PATHS+=("$token")
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

if ! command -v jq &>/dev/null; then
  echo -e "${RED}jq is required.${NC}"
  exit 1
fi

mapfile -t TARGET_REPOS < <(
  if [[ -n "$TARGET_REPOS_RAW" ]]; then
    echo "$TARGET_REPOS_RAW" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | awk '!seen[$0]++'
  fi
)

add_one() {
  local files_path="$1"
  local repos_path="$2"
  local repo_name="$3"
  local repo_file_path="$4"
  local local_path="$5"
  local label="$6"

  local repo_disk_path rmi="" lmi=""
  repo_disk_path=$(jq -r --arg n "$repo_name" '.[] | select(.name == $n) | .path // ""' "$repos_path" | head -1)
  if [[ -n "$repo_disk_path" && "$repo_disk_path" != "null" ]]; then
    local full_master="$PROJECT_ROOT/$repo_disk_path/$repo_file_path"
    [[ -f "$full_master" ]] && rmi=$(file_sync_mtime_iso "$full_master")
  fi
  local full_local="$PROJECT_ROOT/$local_path"
  [[ -f "$full_local" ]] && lmi=$(file_sync_mtime_iso "$full_local")

  local new_entry
  new_entry=$(jq -n \
    --arg repo "$repo_name" \
    --arg repo_path "$repo_file_path" \
    --arg local "$local_path" \
    --arg rmi "${rmi:-}" \
    --arg lmi "${lmi:-}" \
    '{
      repo_name: $repo,
      repo_file_path: $repo_path,
      local_path: $local,
      sync_status: "sync_required",
      last_sync_at: null,
      last_check_at: null,
      repo_file_modified_at: (if $rmi == "" then null else $rmi end),
      local_file_modified_at: (if $lmi == "" then null else $lmi end)
    }')

  filesync_files_append_entry "$files_path" "$repos_path" "$repo_name" "$new_entry" || return 1
  echo -e "${GREEN}Added file to ${label}:${NC} repo=$repo_name repo_file_path=$repo_file_path local_path=$local_path"
}

for target_repo in "${TARGET_REPOS[@]}"; do
  if ! jq -e --arg n "$target_repo" 'any(.name == $n)' "$FILESYNC_REPOS_FILE" &>/dev/null; then
    echo -e "${RED}Error: Target repo '$target_repo' is not in current repos.${NC}"
    exit 1
  fi
  target_repo_path=$(jq -r --arg n "$target_repo" '.[] | select(.name == $n) | .path // ""' "$FILESYNC_REPOS_FILE" | head -1)
  if [[ -z "$target_repo_path" || "$target_repo_path" == "null" ]]; then
    echo -e "${RED}Error: Target repo '$target_repo' has no local path.${NC}"
    exit 1
  fi
  ofs="$PROJECT_ROOT/$target_repo_path/.filesync"
  if [[ ! -f "$ofs/$FILESYNC_FILES_NAME" ]] || [[ ! -f "$ofs/$FILESYNC_REPOS_NAME" ]]; then
    echo -e "${RED}Error: Expected $ofs/$FILESYNC_FILES_NAME and $FILESYNC_REPOS_NAME (create that project's .filesync data).${NC}"
    exit 1
  fi
done

for i in "${!REPO_FILE_PATHS[@]}"; do
  add_one "$FILESYNC_FILES_FILE" "$FILESYNC_REPOS_FILE" "$REPO_NAME" "${REPO_FILE_PATHS[$i]}" "${LOCAL_PATHS[$i]}" "current project" || exit 1
done

for target_repo in "${TARGET_REPOS[@]}"; do
  target_repo_path=$(jq -r --arg n "$target_repo" '.[] | select(.name == $n) | .path // ""' "$FILESYNC_REPOS_FILE" | head -1)
  ofs="$PROJECT_ROOT/$target_repo_path/.filesync"
  for i in "${!REPO_FILE_PATHS[@]}"; do
    add_one "$ofs/$FILESYNC_FILES_NAME" "$ofs/$FILESYNC_REPOS_NAME" "$REPO_NAME" "${REPO_FILE_PATHS[$i]}" "${LOCAL_PATHS[$i]}" "project at $target_repo_path" || exit 1
  done
done
