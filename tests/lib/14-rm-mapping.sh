#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/marker-style.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/markers.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/rm-mapping.sh"

td="${LIB_TEST_TMP}"
mkdir -p "${td}/sub"
printf '%s\n' '[{"local_path":"sub/a.txt","repo_id":"testid-r1","repo_file_path":"a.txt","sync_status":"synced"}]' >"${td}/files_rm.json"
if filesync_remove_file_mapping_row "${td}" "${td}/files_rm.json" "sub/a.txt" && [[ "$(jq 'length' "${td}/files_rm.json")" -eq 0 ]]; then
	ok "rm_mapping removes row"
else
	bad "rm_mapping removes row"
fi
if filesync_remove_file_mapping_row "${td}" "${td}/files_rm.json" "missing" 2>/dev/null; then
	bad "rm_mapping should fail when no row"
else
	ok "rm_mapping rejects missing local_path"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
