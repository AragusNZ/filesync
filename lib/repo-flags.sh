#!/usr/bin/env bash
# Per-repo capability flags (global repos.json).

# Args: repos_json_path repo_name
# Exit 0 if check_sync_enabled (default true when absent or null).
filesync_repo_check_sync_enabled() {
  local repos="$1" name="$2"
  [[ -f "$repos" ]] || return 1
  jq -e --arg n "$name" '
    first(.[]? | select(.name == $n)) as $r
    | $r != null
    and (
        ($r.check_sync_enabled | type) != "boolean"
        or $r.check_sync_enabled
      )
  ' "$repos" &>/dev/null
}

# Args: repos_json_path repo_name
filesync_repo_mirror_in_enabled() {
  local repos="$1" name="$2"
  [[ -f "$repos" ]] || return 1
  jq -e --arg n "$name" '
    first(.[]? | select(.name == $n)) as $r
    | $r != null
    and (
        ($r.mirror_in_enabled | type) != "boolean"
        or $r.mirror_in_enabled
      )
  ' "$repos" &>/dev/null
}

# Args: global repos.json (array only), repo_name
# Exit 0 if row exists and merge_using_git is true (field must be boolean).
filesync_repo_merge_using_git_enabled() {
  local repos="$1" name="$2"
  [[ -f "$repos" ]] || return 1
  jq -e --arg n "$name" '
    first(.[]? | select(.name == $n)) as $r
    | $r != null and ($r.merge_using_git | type) == "boolean" and $r.merge_using_git
  ' "$repos" &>/dev/null
}

# Args: assembled CONFIG_FILE (merged state with .repos), repo_name
filesync_assembled_repo_merge_using_git() {
  local config="${1:?}" name="${2:?}"
  jq -e --arg n "$name" '
    .repos | first(.[]? | select(.name == $n)) as $r
    | $r != null and ($r.merge_using_git | type) == "boolean" and $r.merge_using_git
  ' "$config" &>/dev/null
}
