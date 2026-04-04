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
		'[{"name":"origin","path":$p,"url":"","branch":"main"}]' >"${TMP}/seed-13a.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-13a.json"
	jq -n \
		'[{"repo_id":"testid-origin","repo_file_path":"tools/plain.txt","local_path":"tools/plain.txt","sync_status":"synced"}]' \
		>".filesync/files.json"
	_out="$(filesync check 2>&1)" && _ec=0 || _ec=$?
	[[ "${_ec}" -eq 0 ]] || die "check should exit 0 (marker issues are warnings, not fatal), got ${_ec}"
	[[ "${_out}" == *filesync:* ]] || die "check stderr should include filesync: prefix"
	[[ "${_out}" == *plain.txt* ]] || die "check should mention local path"
	jq -e '.[] | select(.local_path=="tools/plain.txt") | .sync_status == "error_master_marker"' ".filesync/files.json" >/dev/null \
		|| die "files.json should record error_master_marker"
	jq -e '.[] | select(.local_path=="tools/plain.txt") | .check_marker_warnings | index("master_no_master_marker") != null' ".filesync/files.json" >/dev/null \
		|| die "files.json should record check_marker_warnings master_no_master_marker"
)

printf '%s\n' '[]' | jq . >"${FILESYNC_HOME}/repos.json"

# Master checkout wrongly still has kind=clone — check warns but can still render/diff.
(
	m2="${TMP}/chk-mm-master2" p2="${TMP}/chk-mm-proj2"
	rm -rf "${m2}" "${p2}"
	mkdir -p "${m2}/tools" "${p2}/tools"
	{
		printf '%s\n' '# filesync kind=clone path=tools/wrong.txt repo=ghost'
		printf '%s\n' 'body'
	} >"${m2}/tools/wrong.txt"
	{
		printf '%s\n' '# filesync kind=clone path=tools/wrong.txt repo=origin'
		printf '%s\n' 'body'
	} >"${p2}/tools/wrong.txt"
	cd "${p2}"
	filesync init
	jq -n --arg p "${m2}" '[{"name":"origin","path":$p,"url":"","branch":"main"}]' >"${TMP}/seed-13b.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-13b.json"
	jq -n '[{"repo_id":"testid-origin","repo_file_path":"tools/wrong.txt","local_path":"tools/wrong.txt","sync_status":"synced"}]' \
		>".filesync/files.json"
	filesync check >/dev/null 2>&1 || die "check should succeed"
	jq -e '.[] | select(.local_path=="tools/wrong.txt") | .check_marker_warnings | index("master_kind_clone") != null' ".filesync/files.json" >/dev/null \
		|| die "expected master_kind_clone in check_marker_warnings"
	jq -e '.[] | select(.local_path=="tools/wrong.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null \
		|| die "content match should leave synced"
)
