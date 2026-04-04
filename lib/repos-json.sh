#!/usr/bin/env bash
# Global repos.json invariants: unique .name per entry.

_LIB_REPOS_JSON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_REPOS_JSON}/paths.sh"

# Print duplicate repo names, one per line (uses "(empty name)" for null/empty .name), or nothing.
filesync_global_repos_duplicate_names() {
  local f="${1:?}"
  [[ -f "$f" ]] || return 0
  jq -r '
    if type != "array" then empty
    else
      (map(.name // "") | group_by(.) | map(select(length > 1) | .[0])
        | map(if . == "" then "(empty name)" else . end) | .[])
    end' "$f" 2>/dev/null
}

# Return 0 if every repo row has boolean merge_using_git (vacuously true for empty array).
filesync_assert_global_repos_have_merge_using_git() {
  local f="${1:?}"
  [[ -f "$f" ]] || return 0
  if ! jq -e 'all(.[]?; (.merge_using_git | type) == "boolean")' "$f" &>/dev/null; then
    echo "filesync: every repo in ${f} must have boolean merge_using_git (run: filesync migrate)" >&2
    return 1
  fi
  return 0
}

# Print one line per repo row whose .path is empty or does not resolve to an existing directory.
# Args: repos_json_path repo_path_root (anchor for relative paths; see filesync_read_repo_path_root)
filesync_global_repos_missing_checkout_lines() {
  local f="${1:?}" rroot="${2:?}" line name p resolved
  [[ -f "$f" ]] || return 0
  jq -e 'type == "array"' "$f" &>/dev/null || return 0
  while IFS= read -r line; do
    name="$(jq -r 'if (.name // "") == "" then "(empty name)" else .name end' <<<"$line")"
    p="$(jq -r '.path // ""' <<<"$line")"
    if [[ -z "$p" ]]; then
      printf '%s\n' "repo '${name}': missing or empty path"
      continue
    fi
    resolved="$(filesync_resolve_repo_checkout_dir "$rroot" "$p" 2>/dev/null)" || true
    if [[ -z "$resolved" ]] || [[ ! -d "$resolved" ]]; then
      printf '%s\n' "repo '${name}': checkout path missing or not a directory: ${p}"
    fi
  done < <(jq -c '.[]' "$f")
}

# Args: repos_json_path repo_id — print global repo .name for that id, or empty if not found.
filesync_repo_name_from_id() {
  local f="${1:?}" id="${2:?}"
  jq -r --arg id "$id" 'first(.[] | select(.id == $id) | .name) // empty' "$f" 2>/dev/null
}

# Args: repos_json_path repo_name — print global repo .id for that name, or empty if not found.
filesync_global_repos_id_for_name() {
  local f="${1:?}" name="${2:?}"
  jq -r --arg n "$name" 'first(.[] | select(.name == $n) | .id) // empty' "$f" 2>/dev/null
}

# Args: repos_json_path repo_name — print global repo .path for that name, or empty if not found.
filesync_global_repos_path_for_name() {
  local f="${1:?}" name="${2:?}"
  jq -r --arg n "$name" 'first(.[] | select(.name == $n) | .path) // empty' "$f" 2>/dev/null
}

# Return 0 if no duplicates; else print errors to stderr and return 1.
filesync_assert_global_repos_unique_names() {
  local f="${1:?}" d
  d="$(filesync_global_repos_duplicate_names "$f")"
  if [[ -n "$d" ]]; then
    echo "filesync: duplicate repo name(s) in ${f} (each name must be unique):" >&2
    while IFS= read -r line; do
      echo "  $line" >&2
    done <<<"$d"
    return 1
  fi
  return 0
}
