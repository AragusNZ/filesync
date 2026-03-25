#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/am-consumer"
master="${TMP}/am-master"
rm -rf "${p}" "${master}"
mkdir -p "${master}" "${p}"

(
	cd "${master}"
	filesync init
	git init -b main 2>/dev/null || git init
	git config user.email ci@test
	git config user.name ci
)

(
	cd "${p}"
	filesync init
	if filesync add-master 2>/dev/null; then
		die "add-master with no args should fail"
	fi
	if filesync add-master onlyrepo 2>/dev/null; then
		die "add-master with no local path should fail"
	fi
)

jq -n \
	--arg mp "../$(basename "${master}")" \
	'[{"name":"origin","path":$mp,"url":"u","branch":"main"}]' >"${p}/.filesync/repos.json"

(
	cd "${p}"
	touch missing.txt
	if filesync add-master origin missing.txt 2>/dev/null; then
		die "add-master should fail when local file has no marker"
	fi
)

(
	cd "${p}"
	{
		echo "promote-body"
		echo "# filesync:sync kind=clone path=tools/promoted.txt repo=origin"
	} >to_promote.txt
	filesync add-master origin to_promote.txt:tools/promoted.txt
	[[ -f "${master}/tools/promoted.txt" ]] || die "add-master should write master file"
	grep -qE 'kind=master' "${master}/tools/promoted.txt" || die "master copy should have master marker"
	jq -e '.[] | select(.local_path=="to_promote.txt")' ".filesync/files.json" >/dev/null || die "files.json should list mapping"
)
