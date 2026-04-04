#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/smug-master"
proj="${TMP}/smug-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "MASTER_V1"
		echo "# filesync kind=master"
	} >tools/x.txt
	git add tools/x.txt
	git commit -q -m init
)

# A: merge_using_git true + consumer git + clean tree → sync leaves a merge-related history (temp branch removed).
mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init --no-repo
	git init -b main
	git config user.email ci@test
	git config user.name ci
	git add .filesync
	git commit -q -m "base project"
	url="file://${master}"
	jq -n \
		--arg url "$url" \
		'[{"name":"origin","path":"../smug-master","url":$url,"branch":"main","merge_using_git":true}]' >"${TMP}/seed-35a.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-35a.json"
	filesync add origin tools/x.txt
	git add -A
	git commit -q -m "track filesync files" || die "commit after add"
	# Bump master so sync must apply content (otherwise sync is already_in_sync and skips git batch).
	{
		echo "MASTER_V2"
		echo "# filesync kind=master"
	} >"${master}/tools/x.txt"
	git -C "${master}" add tools/x.txt
	git -C "${master}" commit -q -m v2
	filesync check >/dev/null || die "check after master bump"
	git add .filesync
	git commit -q -m "refresh status" || die "commit after check"
	filesync sync >/dev/null || die "sync with merge_using_git true should succeed"
	[[ $(git branch 2>/dev/null | grep -c 'filesync/sync' || true) -eq 0 ]] || die "temp sync branch should be removed"
	_gitlog="$(git log --oneline -8 2>/dev/null)"
	[[ "${_gitlog}" == *Merge* || "${_gitlog}" == *filesync:* ]] || die "expected merge or filesync commit in log, got: ${_gitlog}"
	grep -q 'MASTER_V2' tools/x.txt || die "content should match bumped master"
)

# B: merge_using_git true + dirty index → sync refuses (clean tree required).
proj2="${TMP}/smug-proj2"
rm -rf "${proj2}"
mkdir -p "${proj2}"
(
	cd "${proj2}"
	filesync init --no-repo
	git init -b main
	git config user.email ci@test
	git config user.name ci
	git add .filesync
	git commit -q -m base
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../smug-master","url":$url,"branch":"main","merge_using_git":true}]' >"${TMP}/seed-35b.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-35b.json"
	filesync add origin tools/x.txt
	git add -A
	git commit -q -m "track filesync files" || die "commit after add (B)"
	{
		echo "MASTER_FOR_B"
		echo "# filesync kind=master"
	} >"${master}/tools/x.txt"
	git -C "${master}" add tools/x.txt
	git -C "${master}" commit -q -m for-b
	filesync check >/dev/null || die "check (B)"
	git add .filesync
	git commit -q -m "refresh status" || die "commit after check (B)"
	printf 'x\n' >staged-only.txt
	git add staged-only.txt
	set +e
	_out="$(filesync sync 2>&1)"
	_st=$?
	set -e
	[[ "${_st}" -ne 0 ]] || die "sync with dirty tree should fail (exit ${_st})"
	[[ "${_out}" == *"clean git"* ]] || die "expected clean-tree message, got: ${_out}"
)

# C: merge_using_git false + consumer git → direct write; no filesync sync commit message in log.
proj3="${TMP}/smug-proj3"
rm -rf "${proj3}"
mkdir -p "${proj3}"
(
	cd "${proj3}"
	filesync init --no-repo
	git init -b main
	git config user.email ci@test
	git config user.name ci
	git add .filesync
	git commit -q -m base
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../smug-master","url":$url,"branch":"main","merge_using_git":false}]' >"${TMP}/seed-35c.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-35c.json"
	filesync add origin tools/x.txt
	git add -A
	git commit -q -m "track filesync files" || die "commit after add (C)"
	{
		echo "MASTER_V2C"
		echo "# filesync kind=master"
	} >"${master}/tools/x.txt"
	git -C "${master}" add tools/x.txt
	git -C "${master}" commit -q -m v2c
	filesync check >/dev/null || die "check (C)"
	git add .filesync
	git commit -q -m "refresh status" || die "commit after check (C)"
	_before="$(git rev-parse HEAD)"
	filesync sync >/dev/null || die "sync with merge_using_git false should succeed"
	_after="$(git rev-parse HEAD)"
	[[ "${_before}" == "${_after}" ]] || die "expected no new commit on HEAD for direct sync"
	! git log --oneline --grep='filesync: sync' -1 | grep -q . || die "should not create filesync sync commit when merge_using_git false"
	grep -q 'MASTER_V2C' tools/x.txt || die "content should match master (direct)"
)

# D: merge_using_git true + sync -c after master bump without committing files.json first (embedded check dirties only files.json).
proj4="${TMP}/smug-proj4"
rm -rf "${proj4}"
mkdir -p "${proj4}"
(
	cd "${proj4}"
	filesync init --no-repo
	git init -b main
	git config user.email ci@test
	git config user.name ci
	git add .filesync
	git commit -q -m base
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../smug-master","url":$url,"branch":"main","merge_using_git":true}]' >"${TMP}/seed-35d.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-35d.json"
	filesync add origin tools/x.txt
	git add -A
	git commit -q -m "track filesync files" || die "commit after add (D)"
	{
		echo "MASTER_V2D"
		echo "# filesync kind=master"
	} >"${master}/tools/x.txt"
	git -C "${master}" add tools/x.txt
	git -C "${master}" commit -q -m v2d
	filesync sync -c >/dev/null || die "sync -c with merge_using_git true should succeed (D)"
	[[ $(git branch 2>/dev/null | grep -c 'filesync/sync' || true) -eq 0 ]] || die "temp sync branch should be removed (D)"
	grep -q 'MASTER_V2D' tools/x.txt || die "content should match bumped master (D)"
)
