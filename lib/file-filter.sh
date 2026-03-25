#!/usr/bin/env bash
# Match a file row by optional path fragment (substring on local_path or repo_file_path).

# Args: fragment local_path repo_file_path
# Empty or whitespace-only fragment matches all rows.
filesync_file_matches_fragment() {
  local frag="${1:-}"
  local lp="${2:-}"
  local rp="${3:-}"
  frag="${frag#"${frag%%[![:space:]]*}"}"
  frag="${frag%"${frag##*[![:space:]]}"}"
  [[ -z "$frag" ]] && return 0
  [[ "$lp" == *"$frag"* ]] && return 0
  [[ "$rp" == *"$frag"* ]] && return 0
  return 1
}

# Write one TSV line per selected .files[] row from the merged config (filesync JSON state).
# Columns: index, repo_name, local_path, repo_file_path, sync_status, last_sync_at
# Args are trimmed like filesync_file_matches_fragment: empty/whitespace repo or fragment means no filter.
# Selection matches list-files: optional exact repo_name, optional substring on local_path or repo_file_path.
filesync_config_file_rows_tsv_to() {
  local out="${1:?}" config="${2:?}" repo="${3:-}" frag="${4:-}"
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  frag="${frag#"${frag%%[![:space:]]*}"}"
  frag="${frag%"${frag##*[![:space:]]}"}"
  jq -r --arg repo "$repo" --arg frag "$frag" '
    .files
    | to_entries[]
    | .key as $idx
    | .value
    | select(
        (if $repo == "" then true else .repo_name == $repo end)
        and (if $frag == "" then true
             else
               ((.local_path // "") | tostring | contains($frag))
               or ((.repo_file_path // "") | tostring | contains($frag))
             end)
      )
    | [
        $idx,
        (.repo_name // ""),
        (.local_path // ""),
        (.repo_file_path // ""),
        (.sync_status // ""),
        (.last_sync_at // "")
      ]
    | @tsv
  ' "$config" > "$out"
}
