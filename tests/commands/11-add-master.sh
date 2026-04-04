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
	if filesync add master 2>/dev/null; then
		die "add-master with no args should fail"
	fi
	if filesync add master onlyrepo 2>/dev/null; then
		die "add-master with no local path should fail"
	fi
)

jq -n \
	--arg mp "../$(basename "${master}")" \
	'[{"name":"origin","path":$mp,"url":"u","branch":"main"}]' >"${TMP}/seed-11.json"
filesync_test_seed_global_repos "${p}" "${TMP}/seed-11.json"

(
	cd "${p}"
	touch missing.txt
	if filesync add master origin missing.txt 2>/dev/null; then
		die "add-master should fail when local file has no marker"
	fi
)

(
	cd "${p}"
	{
		echo "promote-body"
		echo "# filesync kind=clone path=tools/promoted.txt repo=origin"
	} >to_promote.txt
	filesync add master origin to_promote.txt:tools/promoted.txt
	[[ -f "${master}/tools/promoted.txt" ]] || die "add-master should write master file"
	grep -qE 'kind=master' "${master}/tools/promoted.txt" || die "master copy should have master marker"
	jq -e '.[] | select(.local_path=="to_promote.txt")' ".filesync/files.json" >/dev/null || die "files.json should list mapping"
)

# Multi-repo collection as master arg must fail (use explicit repo + --also=collection)
p2="${TMP}/am2-consumer"
m2="${TMP}/am2-master"
o2="${TMP}/am2-other"
rm -rf "${p2}" "${m2}" "${o2}"
mkdir -p "${m2}" "${o2}" "${p2}"

(
	cd "${m2}"
	filesync init
	git init -b main 2>/dev/null || git init
	git config user.email ci@test
	git config user.name ci
)
(
	cd "${o2}"
	filesync init
)
(
	cd "${p2}"
	filesync init
)

jq -n \
	--arg mp "../$(basename "${m2}")" \
	--arg op "../$(basename "${o2}")" \
	'[{"name":"origin","path":$mp,"url":"u","branch":"main"},{"name":"other","path":$op,"url":null,"branch":null}]' >"${TMP}/seed-11-multi.json"
filesync_test_seed_global_repos "${p2}" "${TMP}/seed-11-multi.json"
printf '%s\n' '[{"name":"duo","repos":["origin","other"]}]' | jq . >"${FILESYNC_HOME}/collections.json"

(
	cd "${p2}"
	{
		echo "x"
		echo "# filesync kind=clone path=x repo=origin"
	} >multi.txt
	set +e
	_err="$(filesync add master duo multi.txt:x 2>&1)"
	_ec=$?
	set -e
	[[ "${_ec}" -ne 0 ]] || die "add-master should fail for multi-repo collection"
	[[ "${_err}" == *"expands to multiple repos"* ]] || die "expected expands-to-multiple error, got: ${_err}"
)

# Single-member collection resolves like a repo name
p3="${TMP}/am3-consumer"
m3="${TMP}/am3-master"
rm -rf "${p3}" "${m3}"
mkdir -p "${m3}" "${p3}"
(
	cd "${m3}"
	filesync init
	git init -b main 2>/dev/null || git init
	git config user.email ci@test
	git config user.name ci
)
(
	cd "${p3}"
	filesync init
)
jq -n \
	--arg mp "../$(basename "${m3}")" \
	'[{"name":"origin","path":$mp,"url":"u","branch":"main"}]' >"${TMP}/seed-11-solo.json"
filesync_test_seed_global_repos "${p3}" "${TMP}/seed-11-solo.json"
printf '%s\n' '[{"name":"solo","repos":["origin"]}]' | jq . >"${FILESYNC_HOME}/collections.json"

(
	cd "${p3}"
	{
		echo "promote-solo"
		echo "# filesync kind=clone path=tools/solo.txt repo=origin"
	} >to_solo.txt
	filesync add master solo to_solo.txt:tools/solo.txt
	[[ -f "${m3}/tools/solo.txt" ]] || die "add-master with single-member collection should write master file"
)
