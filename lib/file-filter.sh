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

# Write one TSV line per selected .files[] row from the assembled filesync JSON state.
# Columns: index, repo_id, repo_name, local_path, repo_file_path, sync_status, last_sync_at
# Args are trimmed like filesync_file_matches_fragment: empty/whitespace repo or fragment means no filter.
# Optional 5th arg: filter_check_sync — if "1" (default), skip rows whose repo has check_sync_enabled false.
filesync_config_file_rows_tsv_to() {
  local out="${1:?}" config="${2:?}" repo="${3:-}" frag="${4:-}" filter_cs="${5:-1}"
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  frag="${frag#"${frag%%[![:space:]]*}"}"
  frag="${frag%"${frag##*[![:space:]]}"}"
  jq -r --arg repo "$repo" --arg frag "$frag" --arg fcs "$filter_cs" '
    def check_sync_on($n):
      (first(.repos[]? | select(.name == $n)) // null) as $r
      | if $r == null then true
        elif ($r.check_sync_enabled | type) == "boolean" then $r.check_sync_enabled
        else true end;
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
        and (if $fcs == "1" then check_sync_on(.repo_name) else true end)
      )
    | [
        $idx,
        (.repo_id // ""),
        (.repo_name // ""),
        (.local_path // ""),
        (.repo_file_path // ""),
        (.sync_status // ""),
        (.last_sync_at // "")
      ]
    | @tsv
  ' "$config" > "$out"
}

# True (exit 0) if some rows match repo+fragment but none have check_sync_enabled (all blocked).
# Args: config repo_filter file_fragment (trimmed like rows_tsv)
filesync_files_only_blocked_by_check_sync() {
  local config="${1:?}" repo="${2:-}" frag="${3:-}"
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  frag="${frag#"${frag%%[![:space:]]*}"}"
  frag="${frag%"${frag##*[![:space:]]}"}"
  jq -e --arg repo "$repo" --arg frag "$frag" '
    def row_match($row):
      ($row.repo_name // "") as $rn
      | (if $repo == "" then true else $rn == $repo end)
      and (if $frag == "" then true else
        ((($row.local_path // "") | tostring) | contains($frag))
        or ((($row.repo_file_path // "") | tostring) | contains($frag))
      end);
    def check_on($n):
      (first(.repos[]? | select(.name == $n)) // null) as $r
      | if $r == null then true
        elif ($r.check_sync_enabled | type) == "boolean" then $r.check_sync_enabled
        else true end;
    (any(.files[]?; row_match(.))) as $any_m
    | (any(.files[]?; row_match(.) and check_on(.repo_name))) as $any_ok
    | $any_m and ($any_ok | not)
  ' "$config" &>/dev/null
}
