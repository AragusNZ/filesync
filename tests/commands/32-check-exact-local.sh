#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/chk-exact-master" proj="${TMP}/chk-exact-proj"
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
		'[{"name":"origin","path":$p,"url":"","branch":"main"}]' >"${TMP}/seed-32.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-32.json"
	jq -n \
		'[
			{"repo_name":"origin","repo_file_path":"tools/a.txt","local_path":"tools/a.txt","sync_status":"synced","last_check_at":null},
			{"repo_name":"origin","repo_file_path":"tools/b.txt","local_path":"tools/b.txt","sync_status":"synced","last_check_at":null}
		]' >".filesync/files.json"

	filesync check --exact-local=tools/a.txt >/dev/null 2>&1 || die "check --exact-local should succeed"
	jq -e '.[] | select(.local_path=="tools/a.txt") | .last_check_at != null' ".filesync/files.json" >/dev/null \
		|| die "a.txt should be rechecked"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .last_check_at == null' ".filesync/files.json" >/dev/null \
		|| die "b.txt should not be selected by --exact-local=tools/a.txt"
)
