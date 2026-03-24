#!/usr/bin/env bash
# Append a file mapping entry to a files JSON array file (atomic).

# Args: files_path repos_path repo_name entry_json_object_string
filesync_files_append_entry() {
  local files_path="$1"
  local repos_path="$2"
  local repo_name="$3"
  local entry_json="$4"

  if ! jq -e --arg n "$repo_name" 'type == "array" and any(.name == $n)' "$repos_path" &>/dev/null; then
    echo "filesync: repo '$repo_name' not found in $(basename "$repos_path")" >&2
    return 1
  fi

  local lp
  lp=$(echo "$entry_json" | jq -r '.local_path')
  if jq -e --arg local "$lp" '.[] | select(.local_path == $local)' "$files_path" &>/dev/null; then
    echo "filesync: local_path '$lp' already exists in $(basename "$files_path")" >&2
    return 1
  fi

  jq --argjson entry "$entry_json" '. + [$entry]' "$files_path" > "${files_path}.tmp"
  mv "${files_path}.tmp" "$files_path"
}
