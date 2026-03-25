#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/afm-master"
proj="${TMP}/afm-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}/tools" "${proj}"

(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	echo "plain-body" >tools/plain.txt
	git add tools/plain.txt
	git commit -q -m init
)

(
	cd "${proj}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../afm-master","url":$url,"branch":"main"}]' >".filesync/repos.json"
	set +e
	filesync add-file origin tools/plain.txt >/dev/null 2>&1
	_ec=$?
	set -e
	[[ "${_ec}" -ne 0 ]] || die "add-file without master marker should fail"
	filesync add-file --mark-master origin tools/plain.txt
	grep -qE 'kind=master' "${master}/tools/plain.txt" || die "--mark-master should tag master file"
	[[ -f tools/plain.txt ]] || die "add-file should create local"
	grep -qE 'kind=clone' tools/plain.txt || die "local should have clone marker"
)

echo "# filesync kind=clone path=x repo=y" >"${master}/tools/bad.txt"
(
	cd "${master}"
	git add tools/bad.txt
	git commit -q -m bad
)
(
	cd "${proj}"
	set +e
	filesync add-file origin tools/bad.txt:tools/bad-local.txt >/dev/null 2>&1
	_ec=$?
	set -e
	[[ "${_ec}" -ne 0 ]] || die "add-file should fail when master has non-master marker"
)
