#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/push-all-master"
proj="${TMP}/push-all-proj"
rm -rf "${master}" "${proj}"

mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "A_V1"
		echo "# filesync kind=master"
	} >tools/a.txt
	{
		echo "B_V1"
		echo "# filesync kind=master"
	} >tools/b.txt
	git add tools/a.txt tools/b.txt
	git commit -q -m init
)

mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../push-all-master","url":$url,"branch":"main"}]' >".filesync/repos.json"

	filesync add-file origin tools/a.txt
	filesync add-file origin tools/b.txt
	filesync sync
	filesync check >/dev/null || die "check after sync"
	# Ensure local mtime is strictly after last_sync_at (second resolution).
	sleep 1

	echo "EDIT_A" >>tools/a.txt
	filesync check >/dev/null || die "check after local edit"
	jq -e '.[] | select(.local_path=="tools/a.txt") | .sync_status == "local_newer"' ".filesync/files.json" >/dev/null \
		|| die "expected tools/a.txt local_newer"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null \
		|| die "expected tools/b.txt still synced"

	_out="$(filesync push --all 2>&1)" || die "push --all failed: ${_out}"
	[[ "${_out}" == *tools/a.txt* ]] || die "push --all should mention pushed path a: ${_out}"

	jq -e '.[] | select(.local_path=="tools/a.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null \
		|| die "expected tools/a.txt synced after push --all"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null \
		|| die "expected tools/b.txt still synced"
)

grep -q "EDIT_A" "${master}/tools/a.txt" || die "push --all should update master a.txt"
grep -q "^B_V1$" "${master}/tools/b.txt" || die "push --all must not change master b.txt"

# No local_newer: --all succeeds with notice only
noop="${TMP}/push-all-noop-proj"
rm -rf "${noop}"
mkdir -p "${noop}"
(
	cd "${noop}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../push-all-master","url":$url,"branch":"main"}]' >".filesync/repos.json"
	filesync add-file origin tools/a.txt
	filesync sync
	filesync check >/dev/null || die "noop check"
	_no="$(filesync push --all 2>&1)" && _ec=0 || _ec=$?
	[[ "${_ec}" -eq 0 ]] || die "push --all with no local_newer should exit 0, got ${_ec}: ${_no}"
	[[ "${_no}" == *local_newer* ]] || die "expected notice about no local_newer: ${_no}"
)
