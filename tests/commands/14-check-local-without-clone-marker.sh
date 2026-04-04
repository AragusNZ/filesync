#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

# Local may lack kind=clone (e.g. still a raw master copy); check should diff
# rendered clone vs disk and report sync_required, not error_no_clone_marker.

master="${TMP}/chk-noclone-master" proj="${TMP}/chk-noclone-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}/tools"
{
	printf '%s\n' '# filesync kind=master'
	printf '%s\n' 'body line'
} >"${master}/tools/plain.txt"
mkdir -p "${proj}/tools"
cp "${master}/tools/plain.txt" "${proj}/tools/plain.txt"

(
	cd "${proj}"
	filesync init
	jq -n \
		--arg p "${master}" \
		'[{"name":"origin","path":$p,"url":"","branch":"main"}]' >"${TMP}/seed-14.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-14.json"
	jq -n \
		'[{"repo_id":"testid-origin","repo_file_path":"tools/plain.txt","local_path":"tools/plain.txt","sync_status":"synced"}]' \
		>".filesync/files.json"
	_out="$(filesync check 2>&1)" && _ec=0 || _ec=$?
	[[ "${_ec}" -eq 0 ]] || die "check should exit 0 (sync_required is non-blocking), got ${_ec}: ${_out}"
	jq -e '.[] | select(.local_path=="tools/plain.txt") | .sync_status == "sync_required"' ".filesync/files.json" >/dev/null \
		|| die "files.json should record sync_required, not error_no_clone_marker"
	jq -e '.[] | select(.local_path=="tools/plain.txt") | .check_marker_warnings | index("local_kind_master") != null' ".filesync/files.json" >/dev/null \
		|| die "expected local_kind_master warning"
	jq -e '.[] | select(.local_path=="tools/plain.txt") | .check_marker_warnings | index("local_no_clone_marker") != null' ".filesync/files.json" >/dev/null \
		|| die "expected local_no_clone_marker warning"
)
