#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/rmf-am-master"
proj="${TMP}/rmf-am-proj"
rm -rf "${master}" "${proj}"

mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "A"
		echo "# filesync kind=master"
	} >tools/a.txt
	{
		echo "B"
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
		'[{"name":"origin","path":"../rmf-am-master","url":$url,"branch":"main"}]' >"${TMP}/seed-26.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-26.json"

	filesync add-file origin tools/a.txt
	filesync add-file origin tools/b.txt
	filesync sync
	filesync check >/dev/null || die "check after sync"

	rm -f "../rmf-am-master/tools/a.txt"
	filesync check >/dev/null || true
	jq -e '.[] | select(.local_path=="tools/a.txt") | .sync_status == "error_missing_master"' ".filesync/files.json" >/dev/null \
		|| die "expected tools/a.txt error_missing_master"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null \
		|| die "expected tools/b.txt synced"

	_out="$(filesync rmf --all-missing 2>&1)" || die "rmf --all-missing failed: ${_out}"
	[[ "${_out}" == *tools/a.txt* ]] || die "rmf --all-missing should mention removed path a: ${_out}"

	jq -e '.[] | select(.local_path=="tools/a.txt")' ".filesync/files.json" >/dev/null 2>&1 && die "tools/a.txt row should be gone"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null \
		|| die "expected tools/b.txt still present and synced"
)

# No error_missing_master: --all-missing succeeds with notice only
noop="${TMP}/rmf-am-noop"
rm -rf "${noop}"
mkdir -p "${noop}"
(
	cd "${noop}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../rmf-am-master","url":$url,"branch":"main"}]' >"${TMP}/seed-26b.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-26b.json"
	filesync add-file origin tools/b.txt
	filesync sync
	filesync check >/dev/null || die "noop check"
	_no="$(filesync rmf --all-missing 2>&1)" && _ec=0 || _ec=$?
	[[ "${_ec}" -eq 0 ]] || die "rmf --all-missing with no error_missing_master should exit 0, got ${_ec}: ${_no}"
	[[ "${_no}" == *error_missing_master* ]] || die "expected notice about no rows: ${_no}"

	_bad="$(filesync rmf --not-a-flag 2>&1)" && _be=0 || _be=$?
	[[ "${_be}" -eq 1 ]] || die "rmf unknown option should exit 1, got ${_be}: ${_bad}"
	[[ "${_bad}" == *Unknown*option* ]] || die "expected Unknown option message: ${_bad}"
)
