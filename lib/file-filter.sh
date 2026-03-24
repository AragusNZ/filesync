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
