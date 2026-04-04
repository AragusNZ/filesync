#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/sync-ff-master" proj="${TMP}/sync-ff-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "A1"
		echo "# filesync kind=master"
	} >tools/a.txt
	{
		echo "B1"
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
		'[{"name":"origin","path":"../sync-ff-master","url":$url,"branch":"main"}]' >"${TMP}/seed-38-ff.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-38-ff.json"
	filesync add origin tools/a.txt
	filesync add origin tools/b.txt
	filesync sync
	sleep 1
	echo "LOCAL_A" >>tools/a.txt
	touch tools/a.txt
	filesync check >/dev/null || die "check after edit a"
	jq -e '.[] | select(.local_path=="tools/a.txt") | .sync_status == "local_newer"' ".filesync/files.json" >/dev/null \
		|| die "a should be local_newer"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null \
		|| die "b should stay synced"

	_skip="$(filesync sync --file=tools/a.txt 2>&1)" || true
	[[ "${_skip}" == *"not selected; status=local_newer"* ]] || die "--file=a.txt without -f should skip local_newer"
	[[ "${_skip}" != *"tools/b.txt"* ]] || die "filter a must not mention b.txt"

	_out_b="$(filesync sync --file=tools/b.txt 2>&1)" || die "sync --file=b: ${_out_b}"
	[[ "${_out_b}" == *"tools/b.txt"* ]] || die "should process b: ${_out_b}"
)
