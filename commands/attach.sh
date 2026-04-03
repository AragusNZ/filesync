#!/usr/bin/env bash
# Re-couple a detached mapping: refresh clone from master, clear status, run check for that file.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync attach file <local_path> [<local_path> ...]
Also: da, da -f

Re-couple detached mappings: refresh from master, clear status, run check for each file.
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"

trap 'filesync_progress_end || true; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

# Populated by lib/repo-resolve.sh (sourced via runtime with shellcheck source=/dev/null).
# shellcheck disable=SC2034
declare -A FILESYNC_REPO_DIR_CACHE
# shellcheck disable=SC2034
declare -a FILESYNC_CLONED_TEMP_DIRS

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: filesync attach file <local_path1> [local_path2 ...]${NC}" >&2
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

_apaths=${#LOCAL_PATHS[@]}
if filesync_progress_want "$_apaths"; then
  filesync_progress_begin "$_apaths"
fi
_api=0

attach_one() {
  local local_path="$1"
  local full="$PROJECT_ROOT/$local_path"

  if ! jq -e --arg local "$local_path" 'any(.local_path == $local)' "$FILESYNC_FILES_FILE" &>/dev/null; then
    echo -e "${RED}Error: No mapping for local_path '$local_path'.${NC}" >&2
    return 1
  fi

  local prior
  prior="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .sync_status // ""' "$FILESYNC_FILES_FILE")"
  if [[ "$prior" != "detached" ]]; then
    echo -e "${YELLOW}Skip:${NC} $local_path is not detached (sync_status=${prior:-unset}); nothing to attach." >&2
    return 0
  fi

  local repo_file_path repo_name repo_id
  repo_file_path="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .repo_file_path // ""' "$FILESYNC_FILES_FILE")"
  repo_name="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .repo_name // ""' "$FILESYNC_FILES_FILE")"
  repo_id="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .repo_id // ""' "$FILESYNC_FILES_FILE")"

  if [[ -z "$repo_name" || "$repo_name" == "null" ]]; then
    echo -e "${RED}Error: Missing repo_name for $local_path${NC}" >&2
    return 1
  fi

  local repo_root
  if ! repo_root=$(filesync_get_repo_dir "$repo_name"); then
    echo -e "${RED}Error: Could not resolve repo $repo_name${NC}" >&2
    return 1
  fi

  local full_master="$repo_root/$repo_file_path"
  if [[ ! -f "$full_master" ]]; then
    echo -e "${RED}Error: Master file not found: $repo_name/$repo_file_path${NC}" >&2
    return 1
  fi

  jq --arg local "$local_path" 'map(if .local_path == $local then del(.sync_status) else . end)' \
    "$FILESYNC_FILES_FILE" > "${FILESYNC_FILES_FILE}.tmp"
  mv "${FILESYNC_FILES_FILE}.tmp" "$FILESYNC_FILES_FILE"

  mkdir -p "$(dirname "$full")"
  if ! render_clone_from_master_file "$full_master" "$repo_file_path" "$repo_name" "$full" "$repo_id"; then
    filesync_error "${local_path}: could not render clone from master ${repo_name}/${repo_file_path} (master file missing or unparsable filesync marker)"
    return 1
  fi
  echo -e "${GREEN}Re-coupled from master:${NC} $local_path" >&2

  bash "$_CMD_ROOT/check.sh" --repo="$repo_name" --file="$local_path"
}

for lp in "${LOCAL_PATHS[@]}"; do
  attach_one "$lp" || filesync_die "attach failed for one or more paths (see messages above)"
  _api=$((_api + 1))
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    filesync_progress_update "$_api"
  fi
done

filesync_progress_end
