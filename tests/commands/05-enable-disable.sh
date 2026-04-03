#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/ed-master"
proj="${TMP}/ed-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "body"
		echo "# filesync kind=master"
	} >tools/f.txt
	git add tools/f.txt
	git commit -q -m init
)
mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"r","path":"../ed-master","url":$url,"branch":"main"}]' >"${TMP}/seed-05.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-05.json"
	filesync add r tools/f.txt
	filesync edit repo r --disable
	filesync check >/dev/null || die "check when repo disabled"
	filesync sync >/dev/null || die "sync when repo disabled"
	filesync edit repo r --enable
	filesync check >/dev/null || die "check after enable"
)
