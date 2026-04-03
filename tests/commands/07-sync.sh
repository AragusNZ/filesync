#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/sn-proj"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	if filesync sync 2>/dev/null; then
		die "sync with zero repos should fail"
	fi
)

# --force includes local_newer so master can overwrite local edits (without --status=).
master="${TMP}/sync-force-master" proj="${TMP}/sync-force-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "v1"
		echo "# filesync kind=master"
	} >tools/x.txt
	git add tools/x.txt
	git commit -q -m init
)
mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../sync-force-master","url":$url,"branch":"main"}]' >"${TMP}/seed-07.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-07.json"
	filesync add-file origin tools/x.txt
	filesync sync
	# Ensure last_sync_at is strictly before the next local mtime (second resolution).
	sleep 1
	echo "LOCAL_LINE" >>tools/x.txt
	filesync check >/dev/null || die "check after local edit"
	jq -e '.[] | select(.local_path=="tools/x.txt") | .sync_status == "local_newer"' ".filesync/files.json" >/dev/null \
		|| die "expected local_newer status"
	_skip="$(filesync sync --file=x.txt 2>&1)" || true
	[[ "${_skip}" == *"not selected; status=local_newer"* ]] || die "sync without --force should skip local_newer"
	[[ "${_skip}" == *"Sync report:"* ]] || die "sync should print Sync report summary"
	filesync sync -f --file=x.txt
	if grep -q "LOCAL_LINE" tools/x.txt; then
		die "sync with -f/--force should replace file from master"
	fi
	grep -q '^v1$' tools/x.txt || die "local file should match master content"
	_out_none="$(filesync sync --status=conflict --file=x.txt 2>&1)" || true
	[[ "${_out_none}" == *"Sync report:"* ]] || die "status-filtered sync should print Sync report summary"
	[[ "${_out_none}" == *"Nothing to sync (1 already in sync, 1 status-skipped)"* ]] \
		|| die "status-filtered synced rows should contribute to already in sync summary"

	# --check refreshes stale status before selection, so sync_required can be synced.
	sleep 1
	echo "v2" >"${master}/tools/x.txt"
	echo "# filesync kind=master" >>"${master}/tools/x.txt"
	git -C "${master}" add tools/x.txt
	git -C "${master}" commit -q -m v2
	_out_stale="$(filesync sync --file=x.txt 2>&1)" || true
	[[ "${_out_stale}" == *"not selected; status=synced"* ]] || die "without --check, stale synced status should skip"
	_out_checked="$(filesync sync -c --file=x.txt 2>&1)" || die "sync -c should run check then sync"
	[[ "${_out_checked}" == *"Check"* ]] || die "sync -c should run check output first"
	grep -q '^v2$' tools/x.txt || die "sync -c should pull updated master content"
)
