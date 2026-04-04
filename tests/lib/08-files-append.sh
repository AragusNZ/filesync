#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/files-append.sh"

td="${LIB_TEST_TMP}"
printf '%s\n' '[{"name":"r1","path":"repodir","url":"","branch":"main","id":"id-r1","merge_using_git":false}]' >"${td}/repos_fa.json"
printf '%s\n' '[]' >"${td}/files_fa.json"
entry='{"local_path":"tools/x.txt","repo_id":"id-r1","repo_file_path":"tools/x.txt","sync_status":"synced"}'
if filesync_files_append_entry "${td}/files_fa.json" "${td}/repos_fa.json" "r1" "${entry}" && [[ "$(jq 'length' "${td}/files_fa.json")" -eq 1 ]]; then
	ok "files_append_entry"
else
	bad "files_append_entry"
fi
if filesync_files_append_entry "${td}/files_fa.json" "${td}/repos_fa.json" "r1" "${entry}" 2>/dev/null; then
	bad "files_append duplicate should fail"
else
	ok "files_append rejects duplicate local_path"
fi
if filesync_files_append_entry "${td}/files_fa.json" "${td}/repos_fa.json" "missing" "${entry}" 2>/dev/null; then
	bad "files_append missing repo should fail"
else
	ok "files_append rejects unknown repo"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
