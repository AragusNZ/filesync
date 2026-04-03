#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/repos-json.sh"

td="${LIB_TEST_TMP}"
good="${td}/repos-good.json"
bad="${td}/repos-dup.json"
jq -n '[{name:"a",id:"1"},{name:"b",id:"2"}]' >"$good"
if [[ -z "$(filesync_global_repos_duplicate_names "$good")" ]] && filesync_assert_global_repos_unique_names "$good"; then
	ok "repos unique names accepted"
else
	bad "repos unique names should pass"
fi

jq -n '[{name:"same",id:"1"},{name:"same",id:"2"}]' >"$bad"
if [[ -n "$(filesync_global_repos_duplicate_names "$bad")" ]] && ! filesync_assert_global_repos_unique_names "$bad" 2>/dev/null; then
	ok "repos duplicate names rejected"
else
	bad "repos duplicate names should fail assert"
fi

anchor="${td}/rj-anchor"
mkdir -p "${anchor}/present"
abs_anchor="$(cd "$anchor" && pwd)"
ok_rel="${td}/repos-path-ok.json"
jq -n --arg p "present" '[{name:"ok",path:$p,url:null,branch:"main",id:"x",merge_using_git:false}]' >"$ok_rel"
if [[ -z "$(filesync_global_repos_missing_checkout_lines "$ok_rel" "$abs_anchor")" ]]; then
	ok "repos checkout lines empty when path exists"
else
	bad "expected no missing-checkout lines for valid relative path"
fi

bad_rel="${td}/repos-path-bad.json"
jq -n '[{name:"gone",path:"nope",url:null,branch:"main",id:"y",merge_using_git:false}]' >"$bad_rel"
bl="$(filesync_global_repos_missing_checkout_lines "$bad_rel" "$abs_anchor")"
if echo "$bl" | grep -qF "gone" && echo "$bl" | grep -qF "nope"; then
	ok "repos checkout lines report missing relative path"
else
	bad "expected missing-checkout line for bad relative path"
fi

bad_empty="${td}/repos-path-empty.json"
jq -n '[{name:"nopath",path:"",url:null,branch:"main",id:"z",merge_using_git:false}]' >"$bad_empty"
el="$(filesync_global_repos_missing_checkout_lines "$bad_empty" "$abs_anchor")"
if echo "$el" | grep -qF "nopath" && echo "$el" | grep -qF "empty path"; then
	ok "repos checkout lines report empty path"
else
	bad "expected missing-checkout line for empty path"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
