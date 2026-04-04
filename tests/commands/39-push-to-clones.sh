#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/ptc-master"
proj_a="${TMP}/ptc-proj-a"
proj_b="${TMP}/ptc-proj-b"
rm -rf "${master}" "${proj_a}" "${proj_b}"

mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	filesync init
	mkdir -p tools
	{
		echo "M_V1"
		echo "# filesync kind=master"
	} >tools/m.txt
	git add tools/m.txt
	git commit -q -m init
)

mkdir -p "${proj_b}"
( cd "${proj_b}" && filesync init )

mkdir -p "${proj_a}"
(
	cd "${proj_a}"
	filesync init
	jq -n \
		--arg m "${master}" \
		--arg b "${proj_b}" \
		'[
			{"name":"origin","path":$m,"url":null,"branch":"main"},
			{"name":"sibling","path":$b,"url":null,"branch":null}
		]' >"${TMP}/seed-39.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-39.json"
	filesync add origin tools/m.txt --also=sibling
	filesync sync
)

(
	cd "${proj_b}"
	filesync sync
)

grep -q "M_V1" "${proj_a}/tools/m.txt" || die "proj_a clone v1"
grep -q "M_V1" "${proj_b}/tools/m.txt" || die "proj_b clone v1"

{
	echo "M_V2"
	echo "# filesync kind=master"
} >"${master}/tools/m.txt"

(
	cd "${proj_a}"
	filesync push --to-clones "${master}/tools/m.txt" || die "push --to-clones failed"
)

grep -q "M_V2" "${proj_a}/tools/m.txt" || die "proj_a should match master v2"
grep -q "M_V2" "${proj_b}/tools/m.txt" || die "proj_b should match master v2"

(
	cd "${proj_a}"
	if filesync push --dry-run 2>/dev/null; then
		die "push --dry-run without --to-clones should fail"
	fi
)

(
	cd "${proj_a}"
	_no="$(filesync push --to-clones "${master}/tools/nope.txt" 2>&1)" && _ec=0 || _ec=$?
	[[ "${_ec}" -eq 1 ]] || die "nonexistent master path should fail, got ${_ec}: ${_no}"
)
