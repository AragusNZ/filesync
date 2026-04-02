#!/usr/bin/env bash
# CLI: filesync add-file — add file mappings to .filesync/files.json (--also updates sibling projects' files.json).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync add-file <repo_name> <path_in_repo>[:<local_path>] ... [options]
Alias: af

Track files from a repo checkout: path_in_repo is relative to the repo root. If local_path
is omitted (no :suffix), it defaults to the same path as path_in_repo.

Options:
  --mark-master        Set kind=master on the local file (promote as master source)
  --also=names         Comma-separated repo names and/or collection names (see collections.json)

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/files-append.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

MARK_MASTER=false
TARGET_REPOS_RAW=""
declare -a POSITIONAL_RAW=()

for arg in "$@"; do
  if [[ "$arg" == --also=* ]]; then
    TARGET_REPOS_RAW="${arg#--also=}"
  elif [[ "$arg" == --mark-master ]]; then
    MARK_MASTER=true
  elif [[ "$arg" == --* ]]; then
    echo -e "${RED}Error: Unknown option '$arg'.${NC}" >&2
    exit 1
  else
    POSITIONAL_RAW+=("$arg")
  fi
done

if [[ ${#POSITIONAL_RAW[@]} -lt 2 ]]; then
  echo -e "${RED}Usage: filesync add-file <repo_name> <path_in_repo> ... [--mark-master] [--also=names]${NC}" >&2
  exit 1
fi

REPO_NAME="${POSITIONAL_RAW[0]}"
declare -a POSITIONAL=("${POSITIONAL_RAW[@]:1}")
declare -a REPO_FILE_PATHS=()
declare -a LOCAL_PATHS=()

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
    echo -e "${RED}Error: Duplicate local_path '$local_path'.${NC}" >&2
    exit 1
  fi
  SEEN_LOCAL_PATHS["$local_path"]=1
done

declare -a TARGET_REPOS=()
if ! filesync_also_expand_to_array "$TARGET_REPOS_RAW" "$FILESYNC_REPOS_FILE" "$FILESYNC_COLLECTIONS_FILE" TARGET_REPOS; then
  exit 1
fi

add_one() {
  local project_root="$1"
  local files_path="$2"
  local repos_path="$3"
  local path_mode="$4"
  local repo_name="$5"
  local repo_file_path="$6"
  local local_path="$7"
  local label="$8"

  local repo_path_from_json repo_dir rmi="" lmi=""
  repo_path_from_json=$(jq -r --arg n "$repo_name" '.[] | select(.name == $n) | .path // ""' "$repos_path" | head -1)
  repo_dir="$(filesync_resolve_repo_path "$project_root" "$repo_path_from_json" "$path_mode")"
  if [[ -z "$repo_dir" ]]; then
    echo -e "${RED}Error: Repo '$repo_name' has no resolvable local path (${label}).${NC}" >&2
    return 1
  fi

  local full_master="$repo_dir/$repo_file_path"
  if [[ ! -f "$full_master" ]]; then
    echo -e "${RED}Error: Master file not in repo checkout (${label}): $repo_file_path${NC}" >&2
    return 1
  fi

  if has_master_file_sync_marker "$full_master"; then
    :
  elif has_any_file_sync_marker "$full_master"; then
    echo -e "${RED}Error: Master file has a filesync marker that is not kind=master: $repo_file_path${NC}" >&2
    return 1
  elif [[ "$MARK_MASTER" == true ]]; then
    if ! prepend_master_marker_to_file "$full_master" "$repo_file_path"; then
      echo -e "${RED}Error: Could not prepend kind=master marker to: $repo_file_path${NC}" >&2
      return 1
    fi
    echo -e "${GREEN}Prepended kind=master to master copy:${NC} $repo_file_path" >&2
  else
    echo -e "${RED}Error: Master file has no kind=master marker: $repo_file_path (use --mark-master to add one)${NC}" >&2
    return 1
  fi

  local full_local="$project_root/$local_path"
  mkdir -p "$(dirname "$full_local")"
  local tmp_clone
  tmp_clone="$(mktemp)"
  if ! render_clone_from_master_file "$full_master" "$repo_file_path" "$repo_name" "$tmp_clone"; then
    rm -f "$tmp_clone"
    echo -e "${RED}Error: Could not render clone from master: $repo_file_path${NC}" >&2
    return 1
  fi
  cp "$tmp_clone" "$full_local"
  rm -f "$tmp_clone"

  rmi=$(file_sync_mtime_iso "$full_master")
  lmi=$(file_sync_mtime_iso "$full_local")

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
  echo -e "${GREEN}Added file to ${label}:${NC} repo=$repo_name repo_file_path=$repo_file_path local_path=$local_path" >&2
}

for target_repo in "${TARGET_REPOS[@]}"; do
  if ! jq -e --arg n "$target_repo" 'any(.name == $n)' "$FILESYNC_REPOS_FILE" &>/dev/null; then
    echo -e "${RED}Error: Target repo '$target_repo' is not in current repos.${NC}" >&2
    exit 1
  fi
  # shellcheck disable=SC2153  # PROJECT_ROOT and PATH_MODE are set by filesync_command_init.
  target_project_root="$(filesync_resolve_also_project_root "$PROJECT_ROOT" "$FILESYNC_REPOS_FILE" "$target_repo" "$PATH_MODE")"
  if [[ -z "$target_project_root" ]]; then
    echo -e "${RED}Error: Target repo '$target_repo' has no local path.${NC}" >&2
    exit 1
  fi
  ofs="$target_project_root/.filesync"
  if [[ ! -f "$ofs/$FILESYNC_FILES_NAME" ]] || [[ ! -f "$ofs/$FILESYNC_REPOS_NAME" ]]; then
    echo -e "${RED}Error: Target '$target_repo' is not an initialized filesync project: missing $ofs/$FILESYNC_FILES_NAME and/or $ofs/$FILESYNC_REPOS_NAME.${NC}" >&2
    exit 1
  fi
done

for i in "${!REPO_FILE_PATHS[@]}"; do
  add_one "$PROJECT_ROOT" "$FILESYNC_FILES_FILE" "$FILESYNC_REPOS_FILE" "$PATH_MODE" "$REPO_NAME" "${REPO_FILE_PATHS[$i]}" "${LOCAL_PATHS[$i]}" "current project" \
    || filesync_die "add-file failed (see messages above)"
done

for target_repo in "${TARGET_REPOS[@]}"; do
  target_project_root="$(filesync_resolve_also_project_root "$PROJECT_ROOT" "$FILESYNC_REPOS_FILE" "$target_repo" "$PATH_MODE")"
  ofs="$target_project_root/.filesync"
  target_mode="$(filesync_project_read_path_mode "$target_project_root")"
  for i in "${!REPO_FILE_PATHS[@]}"; do
    add_one "$target_project_root" "$ofs/$FILESYNC_FILES_NAME" "$ofs/$FILESYNC_REPOS_NAME" "$target_mode" "$REPO_NAME" "${REPO_FILE_PATHS[$i]}" "${LOCAL_PATHS[$i]}" "project at $target_project_root" \
      || filesync_die "add-file failed (see messages above)"
  done
done
