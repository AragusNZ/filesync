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
if ! filesync_file_matches_fragment "bar" "a" "z/bar/b"; then ok "fragment only in repo_path does not match"; else bad "repo_path should not match"; fi
if ! filesync_file_matches_fragment "zzz" "a" "b"; then ok "non-match"; else bad "should not match"; fi

if filesync_repo_path_matches_file_fragments "z/bar/b" "bar" "x"; then ok "repo_path fragment match"; else bad "repo frag"; fi
if ! filesync_repo_path_matches_file_fragments "a/b" "zzz"; then ok "repo_path non-match"; else bad "repo no match"; fi
if filesync_either_path_matches_file_fragments "a/x" "m/y" "m/y"; then ok "either matches repo side"; else bad "either repo"; fi
if ! filesync_either_path_matches_file_fragments "a/x" "m/y" "zzz"; then ok "either non-match"; else bad "either zzz"; fi

_cfg=$(mktemp)
_out=$(mktemp)
trap 'rm -f "$_cfg" "$_out"' EXIT
jq -n '{files:[
  {repo_id:"id1",repo_name:"r1",local_path:"a/x.txt",repo_file_path:"m/a.txt",sync_status:"synced"},
  {repo_id:"id2",repo_name:"r2",local_path:"b/x.txt",repo_file_path:"m/b.txt",sync_status:"sync_required"}
], repos:[]}' >"$_cfg"
_empty2='[]'
_fx=$(jq -n --arg f x.txt '[$f]')
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "$_fx" "$_empty2" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 2 ]] || bad "tsv fragment should match two rows"
filesync_config_row_r1=$(grep $'^0\t' "$_out" || true)
[[ -n "$filesync_config_row_r1" ]] || bad "row 0 should be first by index"
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "$_empty2" "$_empty2" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 2 ]] || bad "empty frags json should match all rows"
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "r2" "$_empty2" "$_empty2" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 1 ]] || bad "tsv repo filter should match one row"
grep -q $'^1\t' "$_out" || bad "repo r2 row should be index 1"
_fx_trim=$(jq -n --arg f 'x.txt' '[$f]')
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "  r2 " "$_fx_trim" "$_empty2" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 1 ]] || bad "tsv trim repo + fragment"
grep -q $'^1\t' "$_out" || bad "filtered row should be index 1"
ok "config_file_rows_tsv_to fragment, repo, trim"

_fa=$(jq -n --arg f 'a/x.txt' '[$f]')
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "$_fa" "$_empty2" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 1 ]] || bad "single local fragment should match one row"
grep -q $'^0\tid1\tr1\ta/x\.txt' "$_out" || bad "row should be index 0 r1 a/x.txt"
_fab=$(jq -n --arg a 'a/x.txt' --arg b 'b/x.txt' '[$a,$b]')
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "$_fab" "$_empty2" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 2 ]] || bad "two local fragments should match two rows"
_fm=$(jq -n --arg f 'm/a' '[$f]')
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "$_fm" "$_empty2" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 0 ]] || bad "repo path in --file= must not select rows"
ok "config_file_rows_tsv_to local_path only"

_frp=$(jq -n --arg f 'm/b' '[$f]')
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "$_empty2" "$_frp" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 1 ]] || bad "repo-file fragment should match one row"
grep -q $'^1\t' "$_out" || bad "repo-file row should be r2"

_fall=$(jq -n --arg f 'm/a' '[$f]')
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "$_empty2" "$_empty2" "$_fall"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 1 ]] || bad "all-files by repo path only"
grep -q $'^0\t' "$_out" || bad "all-files m/a should be row 0"

_flb=$(jq -n --arg f 'b/x' '[$f]')
filesync_config_file_rows_tsv_to "$_out" "$_cfg" "" "$_flb" "$_frp" "$_empty2"
[[ "$(wc -l < "$_out" | tr -d " ")" -eq 1 ]] || bad "AND local+repo-file"
grep -q $'^1\t' "$_out" || bad "AND should be r2 row"

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
