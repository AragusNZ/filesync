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

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
