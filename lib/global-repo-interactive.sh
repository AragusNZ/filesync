#!/usr/bin/env bash
# Shared pieces for interactive append to global repos.json (filesync new repo + init wizard).

_LIB_GRI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_GRI}/colors.sh"
# shellcheck source=/dev/null
source "${_LIB_GRI}/paths.sh"
# shellcheck source=/dev/null
source "${_LIB_GRI}/repo-merge-using-git.sh"
# shellcheck source=/dev/null
source "${_LIB_GRI}/repo-id.sh"
# shellcheck source=/dev/null
source "${_LIB_GRI}/fs-lock.sh"

# Args: rroot def_checkout path_default — stderr context lines (same copy for init / new repo).
filesync_global_repo_print_path_banner() {
  echo -e "${GRAY}Repo path root: ${1}${NC}" >&2
  echo -e "${GRAY}Default checkout directory: ${2}${NC}" >&2
  echo -e "${GRAY}Default stored path (relative when possible): ${3}${NC}" >&2
  echo "" >&2
}

# Args: rroot def_checkout path_default — reads one line from stdin; prints stored path on stdout.
# Returns 1 if the path does not resolve to a directory.
filesync_global_repo_prompt_stored_path() {
  local rroot="$1" def_checkout="$2" path_default="$3"
  local path_in path
  read -rp "Checkout path (relative to repo path root above, or absolute) [${path_default}]: " path_in
  path="$(filesync_repos_json_path_from_input "$rroot" "$def_checkout" "$path_in")" || return 1
  printf '%s\n' "$path"
}

# Args: name url path branch rroot — one repo object JSON on stdout. Returns 1 if path does not resolve.
filesync_global_repo_row_json() {
  local name="$1" url="$2" path="$3" branch="$4" rroot="$5"
  local rid checkout_abs mug_json
  rid="$(filesync_new_repo_id)"
  checkout_abs="$(filesync_resolve_repo_checkout_dir "$rroot" "$path")"
  [[ -n "$checkout_abs" ]] || return 1
  if filesync_dir_is_git_worktree "$checkout_abs"; then
    mug_json=true
  else
    mug_json=false
  fi
  jq -n \
    --arg id "$rid" \
    --arg name "$name" \
    --arg url "$url" \
    --arg path "$path" \
    --arg branch "$branch" \
    --argjson merge_using_git "$mug_json" \
    '{id: $id, name: $name, url: $url, path: $path, branch: $branch, check_sync_enabled: true, mirror_in_enabled: true, merge_using_git: $merge_using_git}'
}

# Args: repos_json_path entry_json — requires FILESYNC_SYSTEM_HOME for flock.
filesync_global_repo_append_row_locked() {
  local repos="${1:?}" entry="${2:?}"
  filesync_global_lock_acquire
  trap 'filesync_global_lock_release' EXIT
  jq --argjson entry "$entry" '. + [$entry]' "$repos" >"${repos}.tmp"
  mv "${repos}.tmp" "$repos"
  filesync_global_lock_release
  trap - EXIT
}
