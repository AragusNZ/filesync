#!/usr/bin/env bash
# Global repos.json invariants: unique .name per entry.

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
