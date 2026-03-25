#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/file-filter.sh"

if filesync_file_matches_fragment "" "a" "b"; then ok "empty fragment matches"; else bad "empty fragment"; fi
if filesync_file_matches_fragment "foo" "x/foo" "y"; then ok "fragment in local_path"; else bad "local_path match"; fi
if filesync_file_matches_fragment "bar" "a" "z/bar/b"; then ok "fragment in repo_file_path"; else bad "repo_path match"; fi
if ! filesync_file_matches_fragment "zzz" "a" "b"; then ok "non-match"; else bad "should not match"; fi

_cfg=$(mktemp)
_out=$(mktemp)
trap 'rm -f "$_cfg" "$_out"' EXIT
jq -n '{files:[
  {repo_name:"r1",local_path:"a/x.txt",repo_file_path:"m/a.txt",sync_status:"synced"},
  {repo_name:"r2",local_path:"b/x.txt",repo_file_path:"m/b.txt",sync_status:"sync_required"}
]}' >"$_cfg"
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "x.txt"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 2 ]] || bad "tsv fragment should match two rows"
filesync_config_row_r1=$(grep $'^0\t' "$_out" || true)
[[ -n "$filesync_config_row_r1" ]] || bad "row 0 should be first by index"
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "r2" ""
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 1 ]] || bad "tsv repo filter should match one row"
grep -q $'^1\t' "$_out" || bad "repo r2 row should be index 1"
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "  r2 " $' x.txt\n'
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 1 ]] || bad "tsv trim + combined filter"
grep -q $'^1\t' "$_out" || bad "filtered row should be index 1"
ok "config_file_rows_tsv_to fragment, repo, trim"

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
