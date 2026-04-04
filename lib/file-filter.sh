#!/usr/bin/env bash
# Path fragment filters for file rows: local_path, repo_file_path, or either.

# Args: fragment local_path [ignored]
# Empty or whitespace-only fragment matches all rows (for single-fragment callers/tests).
# Third argument, if present, is ignored (historical; no longer used).
filesync_file_matches_fragment() {
  local frag="${1:-}"
  local lp="${2:-}"
  frag="${frag#"${frag%%[![:space:]]*}"}"
  frag="${frag%"${frag##*[![:space:]]}"}"
  [[ -z "$frag" ]] && return 0
  [[ "$lp" == *"$frag"* ]] && return 0
  return 1
}

# Args: name of bash array holding zero or more fragment values (may include blanks).
# Prints each trimmed nonempty fragment on its own line (for building jq JSON arrays).
filesync_emit_nonempty_file_fragments() {
  local -n __ffa=$1
  local t f
  for f in "${__ffa[@]}"; do
    t="${f#"${f%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [[ -n "$t" ]] && printf '%s\n' "$t"
  done
}

# Args: local_path [fragment ...]
# No fragments, or only whitespace fragments → match all.
# Otherwise → true if local_path contains any trimmed fragment as a substring.
filesync_local_path_matches_file_fragments() {
  local lp="${1:-}"
  shift
  local -a raw=("$@")
  local -a nonempty=()
  local t f
  for f in "${raw[@]}"; do
    t="${f#"${f%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [[ -n "$t" ]] && nonempty+=("$t")
  done
  [[ ${#nonempty[@]} -eq 0 ]] && return 0
  for f in "${nonempty[@]}"; do
    [[ "$lp" == *"$f"* ]] && return 0
  done
  return 1
}

# Args: repo_file_path [fragment ...]
# Same semantics as filesync_local_path_matches_file_fragments for repo_file_path.
filesync_repo_path_matches_file_fragments() {
  local rp="${1:-}"
  shift
  local -a raw=("$@")
  local -a nonempty=()
  local t f
  for f in "${raw[@]}"; do
    t="${f#"${f%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [[ -n "$t" ]] && nonempty+=("$t")
  done
  [[ ${#nonempty[@]} -eq 0 ]] && return 0
  for f in "${nonempty[@]}"; do
    [[ "$rp" == *"$f"* ]] && return 0
  done
  return 1
}

# Args: local_path repo_file_path [fragment ...]
# No nonempty fragments → match all.
# Otherwise → true if any fragment is a substring of local_path OR repo_file_path.
filesync_either_path_matches_file_fragments() {
  local lp="${1:-}"
  local rp="${2:-}"
  shift 2
  local -a raw=("$@")
  local -a nonempty=()
  local t f
  for f in "${raw[@]}"; do
    t="${f#"${f%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [[ -n "$t" ]] && nonempty+=("$t")
  done
  [[ ${#nonempty[@]} -eq 0 ]] && return 0
  for f in "${nonempty[@]}"; do
    [[ "$lp" == *"$f"* ]] && return 0
    [[ "$rp" == *"$f"* ]] && return 0
  done
  return 1
}

# Args: local_path repo_file_path + three namerefs to fragment arrays (local, repo_file, all_files).
filesync_row_matches_path_filter_groups() {
  local lp="${1:?}" rp="${2:?}"
  local -n _fl=$3 _fr=$4 _fa=$5
  filesync_local_path_matches_file_fragments "$lp" "${_fl[@]}" || return 1
  filesync_repo_path_matches_file_fragments "$rp" "${_fr[@]}" || return 1
  filesync_either_path_matches_file_fragments "$lp" "$rp" "${_fa[@]}" || return 1
  return 0
}

# Write one TSV line per selected .files[] row from the assembled filesync JSON state.
# Columns: index, repo_id, repo_name, local_path, repo_file_path, sync_status, last_sync_at
# Args: out config repo local_frags_json repo_frags_json all_frags_json [filter_check_sync]
# Each *frags_json is a JSON string array; [] means no filter in that dimension.
# Dimensions combine with AND; within each, multiple fragments OR.
# all_frags: row matches if any fragment appears in local_path OR repo_file_path.
# Optional 7th arg filter_check_sync — if "1" (default), skip rows whose repo has check_sync_enabled false.
filesync_config_file_rows_tsv_to() {
  local out="${1:?}" config="${2:?}" repo="${3:-}" lf="${4:-[]}" rf="${5:-[]}" af="${6:-[]}" fcs="${7:-1}"
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  jq -r --arg repo "$repo" --argjson lf "$lf" --argjson rf "$rf" --argjson af "$af" --arg fcs "$fcs" '
    def check_sync_on($n):
      (first(.repos[]? | select(.name == $n)) // null) as $r
      | if $r == null then true
        elif ($r.check_sync_enabled | type) == "boolean" then $r.check_sync_enabled
        else true end;
    def row_path_match($row):
      ((($lf | length) == 0) or any($lf[]; . as $frag | (($row.local_path // "") | tostring | contains($frag))))
      and ((($rf | length) == 0) or any($rf[]; . as $frag | (($row.repo_file_path // "") | tostring | contains($frag))))
      and ((($af | length) == 0) or any($af[]; . as $frag |
        ((($row.local_path // "") | tostring | contains($frag))
         or (($row.repo_file_path // "") | tostring | contains($frag)))
      ));
    .files
    | to_entries[]
    | .key as $idx
    | .value as $row
    | select(
        (if $repo == "" then true else $row.repo_name == $repo end)
        and row_path_match($row)
        and (if $fcs == "1" then check_sync_on($row.repo_name) else true end)
      )
    | [
        $idx,
        ($row.repo_id // ""),
        ($row.repo_name // ""),
        ($row.local_path // ""),
        ($row.repo_file_path // ""),
        ($row.sync_status // ""),
        ($row.last_sync_at // "")
      ]
    | @tsv
  ' "$config" > "$out"
}

# True (exit 0) if some rows match repo+path filters but none have check_sync_enabled (all blocked).
# Args: config repo_filter local_frags_json repo_frags_json all_frags_json
filesync_files_only_blocked_by_check_sync() {
  local config="${1:?}" repo="${2:-}" lf="${3:-[]}" rf="${4:-[]}" af="${5:-[]}"
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  jq -e --arg repo "$repo" --argjson lf "$lf" --argjson rf "$rf" --argjson af "$af" '
    def row_path_match($row):
      ((($lf | length) == 0) or any($lf[]; . as $frag | ((($row.local_path // "") | tostring) | contains($frag))))
      and ((($rf | length) == 0) or any($rf[]; . as $frag | ((($row.repo_file_path // "") | tostring) | contains($frag))))
      and ((($af | length) == 0) or any($af[]; . as $frag |
        (((($row.local_path // "") | tostring) | contains($frag))
         or ((($row.repo_file_path // "") | tostring) | contains($frag)))
      ));
    def row_match($row):
      ($row.repo_name // "") as $rn
      | (if $repo == "" then true else $rn == $repo end)
      and row_path_match($row);
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
