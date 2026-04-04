#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/rmr-proj"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	jq -n '[
		{"name":"empty","path":"../noop","url":"","branch":"main"},
		{"name":"busy","path":"../noop2","url":"","branch":"main"}
	]' >"${TMP}/seed-23a.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-23a.json"
	jq -n '[{
		"local_path":"x.txt",
		"repo_id":"testid-busy",
		"repo_file_path":"x.txt",
		"sync_status":"synced"
	}]' >".filesync/files.json"

	filesync remove repo nosuch 2>/dev/null && die "remove-repo missing repo should fail"

	filesync remove repo busy 2>/dev/null && die "remove-repo without --force should fail when mappings exist"
	printf 'n\n' | filesync remove repo busy --force >/dev/null || die "remove-repo decline should exit 0"
	jq -e 'length == 2' "${FILESYNC_HOME}/repos.json" >/dev/null || die "both repos should remain after decline"
	jq -e 'length == 1' ".filesync/files.json" >/dev/null || die "files.json unchanged after decline"

	filesync remove repo empty
	jq -e '[.[] | select(.name == "empty")] | length == 0' "${FILESYNC_HOME}/repos.json" >/dev/null || die "empty repo should be gone"
	jq -e 'length == 1' "${FILESYNC_HOME}/repos.json" >/dev/null || die "busy repo should remain"

	filesync remove repo busy --force -y >/dev/null || die "remove-repo --force -y should succeed without prompt"
	jq -e 'length == 0' "${FILESYNC_HOME}/repos.json" >/dev/null || die "repos.json should be empty"
	jq -e 'length == 0' ".filesync/files.json" >/dev/null || die "files.json should be empty after confirm"
)
# re-init a fresh tree for rmr-only path
p2="${TMP}/rmr-proj2"
mkdir -p "${p2}"
(
	cd "${p2}"
	filesync init
	jq -n '[{"name":"solo","path":"../z","url":"","branch":"main"}]' >"${TMP}/seed-23b.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-23b.json"
	filesync remove repo solo
	jq -e 'length == 0' "${FILESYNC_HOME}/repos.json" >/dev/null || die "solo repo with no files should remove"
)
