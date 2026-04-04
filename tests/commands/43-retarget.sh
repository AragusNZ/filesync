#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/retarget-master"
proj="${TMP}/retarget-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}" "${proj}"

export FILESYNC_HOME="${TMP}/retarget-fs-home"
rm -rf "${FILESYNC_HOME}"
mkdir -p "${FILESYNC_HOME}"
printf '%s\n' '[]' | jq . >"${FILESYNC_HOME}/collections.json"

(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "v1"
		echo "# filesync kind=master"
	} >tools/foo.txt
	git add tools/foo.txt
	git commit -q -m init
)

(
	cd "${proj}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../retarget-master","url":$url,"branch":"main","merge_using_git":false}]' >"${TMP}/retarget-repos.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/retarget-repos.json"

	filesync add origin tools/foo.txt
	filesync sync
	jq -e '.[] | select(.local_path=="tools/foo.txt") | .repo_file_path == "tools/foo.txt"' ".filesync/files.json" >/dev/null || die "expected initial paths"

	cd "${master}"
	git mv tools/foo.txt tools/bar.txt
	git commit -q -m mv

	cd "${proj}"
	# Retarget from clone (JSON still points at missing tools/foo.txt)
	filesync retarget clone tools/foo.txt tools/bar.txt
	jq -e '.[] | select(.local_path=="tools/foo.txt") | .repo_file_path == "tools/bar.txt" and .sync_status == "sync_required"' ".filesync/files.json" >/dev/null \
		|| die "clone retarget should set repo_file_path and sync_required"

	if filesync retarget clone "${master}/tools/bar.txt" tools/bar.txt 2>/dev/null; then
		die "retarget clone with master path should fail"
	fi

	filesync sync
	grep -q '^v1$' tools/foo.txt || die "sync should refresh clone at old local path"

	# Master-at-checkout retarget: move again, point at new master on disk (stale JSON path)
	cd "${master}"
	mkdir -p lib
	git mv tools/bar.txt lib/w.txt
	git commit -q -m mv2

	cd "${proj}"
	# First path absent: anchor from new repo path (master-only fallback)
	filesync retarget master tools/bar.txt lib/w.txt
	jq -e '.[] | select(.local_path=="tools/foo.txt") | .repo_file_path == "lib/w.txt" and .sync_status == "master_file_moved"' ".filesync/files.json" >/dev/null \
		|| die "master retarget without --move should set master_file_moved"

	if filesync retarget master tools/foo.txt lib/w.txt 2>/dev/null; then
		die "retarget master with clone path should fail"
	fi

	[[ -f tools/foo.txt ]] || die "local should stay at tools/foo.txt until sync --move"
	_dry_out="$(filesync sync --dry-run --move 2>&1)" || die "sync --dry-run --move failed"
	printf '%s\n' "$_dry_out" | grep -qF 'dry-run move' || die "dry-run --move should mention move; output:\n${_dry_out}"

	filesync sync --move
	if [[ -f tools/foo.txt ]] || [[ ! -f lib/w.txt ]]; then
		die "sync --move should relocate local file"
	fi
	jq -e '.[] | select(.local_path=="lib/w.txt") | (.sync_status == "synced" or .sync_status == "sync_required" or .sync_status == null)' ".filesync/files.json" >/dev/null \
		|| die "row should exist at new local_path after move+sync"
)

echo "retarget tests OK"
