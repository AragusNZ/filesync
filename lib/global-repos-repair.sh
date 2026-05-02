#!/usr/bin/env bash
# Normalize global repos.json after filesync_ensure_system_store creates defaults.

_LIB_GLOBAL_REPOS_REPAIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_GLOBAL_REPOS_REPAIR}/data-names.sh"
# shellcheck source=/dev/null
source "${_LIB_GLOBAL_REPOS_REPAIR}/repos-json.sh"
# shellcheck source=/dev/null
source "${_LIB_GLOBAL_REPOS_REPAIR}/repo-merge-using-git.sh"
# shellcheck source=/dev/null
source "${_LIB_GLOBAL_REPOS_REPAIR}/fs-lock.sh"

# Repo path anchor for backfill (same rules as system-resolve.sh; kept here to avoid a source cycle).
_filesync_repair_repo_path_root() {
  if [[ -n "${FILESYNC_REPO_PATH_ANCHOR:-}" ]]; then
    (cd "$FILESYNC_REPO_PATH_ANCHOR" && pwd -P)
    return 0
  fi
  (cd "${HOME:?}" && pwd -P)
}

# Args: system metadata directory (absolute). Idempotent. Returns non-zero on unrecoverable catalog state.
filesync_repair_global_repos_json_if_needed() {
  local home="${1:?}"
  local repos="$home/${FILESYNC_GLOBAL_REPOS_NAME}"

  [[ -f "$repos" ]] || return 0

  if ! jq -e . "$repos" &>/dev/null; then
    echo "filesync: ${repos} is not valid JSON; resetting catalog to []" >&2
    printf '%s\n' '[]' | jq . >"${repos}.tmp"
    mv "${repos}.tmp" "$repos"
    return 0
  fi

  if ! jq -e 'type == "array"' "$repos" &>/dev/null; then
    echo "filesync: ${repos} must be a JSON array (fix or remove the file)" >&2
    return 1
  fi

  if jq -e 'all(.[]?; (.merge_using_git | type) == "boolean")' "$repos" &>/dev/null; then
    return 0
  fi

  local rroot
  rroot="$(_filesync_repair_repo_path_root)" || {
    echo "filesync: could not resolve repo path anchor (HOME)" >&2
    return 1
  }
  if [[ -z "$rroot" || "$rroot" == "null" ]]; then
    echo "filesync: could not resolve repo path anchor (HOME)" >&2
    return 1
  fi

  export FILESYNC_SYSTEM_HOME="$home"
  filesync_global_lock_acquire
  trap 'filesync_global_lock_release' EXIT

  if ! jq -e 'type == "array"' "$repos" &>/dev/null; then
    filesync_global_lock_release
    trap - EXIT
    echo "filesync: ${repos} is not a JSON array after lock" >&2
    return 1
  fi

  if jq -e 'all(.[]?; (.merge_using_git | type) == "boolean")' "$repos" &>/dev/null; then
    filesync_global_lock_release
    trap - EXIT
    return 0
  fi

  filesync_repos_json_backfill_merge_using_git "$repos" "$rroot"

  filesync_global_lock_release
  trap - EXIT

  if ! filesync_assert_global_repos_have_merge_using_git "$repos"; then
    echo "filesync: could not satisfy merge_using_git on ${repos} (try: filesync migrate)" >&2
    return 1
  fi
  return 0
}
