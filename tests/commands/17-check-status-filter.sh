#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/chk-status-master" proj="${TMP}/chk-status-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}/tools" "${proj}/tools"

{
	printf '%s\n' '# filesync kind=master'
	printf '%s\n' 'same'
} >"${master}/tools/a.txt"
{
	printf '%s\n' '# filesync kind=master'
	printf '%s\n' 'same'
} >"${master}/tools/b.txt"

{
	printf '%s\n' '# filesync kind=clone path=tools/a.txt repo=origin'
	printf '%s\n' 'same'
} >"${proj}/tools/a.txt"
{
	printf '%s\n' '# filesync kind=clone path=tools/b.txt repo=origin'
	printf '%s\n' 'same'
} >"${proj}/tools/b.txt"

(
	cd "${proj}"
	filesync init
	jq -n \
		--arg p "${master}" \
		'[{"name":"origin","path":$p,"url":"","branch":"main"}]' >".filesync/repos.json"
	jq -n \
		'[
			{"repo_name":"origin","repo_file_path":"tools/a.txt","local_path":"tools/a.txt","sync_status":"local_newer","last_check_at":null},
			{"repo_name":"origin","repo_file_path":"tools/b.txt","local_path":"tools/b.txt","sync_status":"synced","last_check_at":null}
		]' >".filesync/files.json"

	_out="$(filesync check --status=local_newer 2>&1)" && _ec=0 || _ec=$?
	[[ "${_ec}" -eq 0 ]] || die "check --status=local_newer should succeed, got ${_ec}: ${_out}"
	[[ "${_out}" == *"tools/a.txt"* ]] || die "status-filtered check should include a.txt output"
	[[ "${_out}" != *"tools/b.txt"* ]] || die "status-filtered check should not include b.txt output"

	jq -e '.[] | select(.local_path=="tools/a.txt") | .last_check_at != null' ".filesync/files.json" >/dev/null \
		|| die "a.txt should be rechecked"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .last_check_at == null' ".filesync/files.json" >/dev/null \
		|| die "b.txt should remain untouched by status filter"
)
