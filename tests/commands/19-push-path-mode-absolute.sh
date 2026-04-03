#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/abs-master"
proj="${TMP}/abs-proj"
rm -rf "${master}" "${proj}"

mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "ABS_V1"
		echo "# filesync kind=master"
	} >tools/p.txt
	git add tools/p.txt
	git commit -q -m init
)

mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init
	jq -n \
		--arg p "${master}" \
		'[{"name":"origin","path":$p,"url":null,"branch":"main"}]' >"${TMP}/seed-19.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-19.json"

	filesync add-file origin tools/p.txt
	echo "LOCAL_EDIT" >>"tools/p.txt"
	filesync push tools/p.txt
)

grep -q "LOCAL_EDIT" "${master}/tools/p.txt" || die "push should write to absolute-path master"

