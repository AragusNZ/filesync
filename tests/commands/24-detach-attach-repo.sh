#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/dar-master" proj="${TMP}/dar-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}" "${proj}"
master="$(cd "${master}" && pwd -P)"
proj="$(cd "${proj}" && pwd -P)"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "a-v1"
		echo "# filesync kind=master"
	} >tools/a.txt
	{
		echo "b-v1"
		echo "# filesync kind=master"
	} >tools/b.txt
	git add tools/a.txt tools/b.txt
	git commit -q -m init
)
mkdir -p "${proj}"
(
	cd "${proj}"
	# Isolate mktemp(1) so we can detect orphaned FILESYNC_STATE_FILE from attach-repo/exec.
	TMPDIR="$(mktemp -d)"
	export TMPDIR
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../dar-master","url":$url,"branch":"main"}]' >"${TMP}/seed-24.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-24.json"
	filesync add origin tools/a.txt
	filesync add origin tools/b.txt
	filesync sync
	filesync check >/dev/null || die "check before detach-repo"
	filesync detach files-in-repo origin
	jq -e '.[] | select(.local_path=="tools/a.txt") | .sync_status == "detached"' ".filesync/files.json" >/dev/null || die "a detached"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .sync_status == "detached"' ".filesync/files.json" >/dev/null || die "b detached"
	grep -q 'filesync kind=detached' tools/a.txt || die "a marker"
	grep -q 'filesync kind=detached' tools/b.txt || die "b marker"
	filesync attach files-in-repo origin
	jq -e '.[] | select(.local_path=="tools/a.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null || die "a synced"
	jq -e '.[] | select(.local_path=="tools/b.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null || die "b synced"
	grep -q 'filesync kind=clone' tools/a.txt || die "a clone"
	grep -q 'filesync kind=clone' tools/b.txt || die "b clone"
	if filesync detach files-in-repo nosuchrepo_name 2>/dev/null; then
		die "detach-repo unknown repo should fail"
	fi
	if filesync attach files-in-repo nosuchrepo_name 2>/dev/null; then
		die "attach-repo unknown repo should fail"
	fi
	filesync d -fir origin >/dev/null || die "d -fir shorthand"
	filesync da -fir origin >/dev/null || die "da -fir shorthand"
	_sweep="$(find "${TMPDIR}" -type f 2>/dev/null | wc -l)"
	_sweep="${_sweep//[[:space:]]/}"
	[[ "${_sweep}" -eq 0 ]] || die "expected no leaked temps in TMPDIR (got ${_sweep})"
	rm -rf "${TMPDIR}"
)
