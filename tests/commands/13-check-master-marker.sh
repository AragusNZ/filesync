#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/chk-mm-master" proj="${TMP}/chk-mm-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}/tools"
printf '%s\n' 'plain master no marker' >"${master}/tools/plain.txt"
mkdir -p "${proj}/tools"
{
	printf '%s\n' '# filesync kind=clone path=tools/plain.txt repo=origin'
	printf '%s\n' 'local body'
} >"${proj}/tools/plain.txt"

(
	cd "${proj}"
	filesync init
	jq -n \
		--arg p "${master}" \
		'[{"name":"origin","path":$p,"url":"","branch":"main"}]' >".filesync/repos.json"
	jq -n \
		'[{"repo_name":"origin","repo_file_path":"tools/plain.txt","local_path":"tools/plain.txt","sync_status":"synced"}]' \
		>".filesync/files.json"
	_out="$(filesync check 2>&1)" && _ec=0 || _ec=$?
	[[ "${_ec}" -eq 1 ]] || die "check should exit 1 for error_master_marker, got ${_ec}"
	[[ "${_out}" == *filesync:* ]] || die "check stderr should include filesync: prefix"
	[[ "${_out}" == *plain.txt* ]] || die "check should mention local path"
	jq -e '.[] | select(.local_path=="tools/plain.txt") | .sync_status == "error_master_marker"' ".filesync/files.json" >/dev/null \
		|| die "files.json should record error_master_marker"
)
