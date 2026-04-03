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
