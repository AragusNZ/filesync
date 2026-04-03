#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/rl-proj"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	filesync list repos >/dev/null || die "list-repos empty"
	filesync list files >/dev/null || die "list-files empty"
	if filesync list repos --repo=nosuchrepo 2>/dev/null; then
		die "list-repos --repo missing should fail"
	fi
	if filesync list repos --file=x 2>/dev/null; then
		die "list-repos --file should fail"
	fi
	if ! filesync list files --file=nomatch 2>/dev/null; then
		die "list-files --file with zero rows should succeed"
	fi
	if filesync list repos --status=synced 2>/dev/null; then
		die "list-repos --status should fail"
	fi
	printf '%s\n' '[{"repo_name":"r1","repo_file_path":"a.txt","local_path":"a.txt","sync_status":"synced"},{"repo_name":"r1","repo_file_path":"b.txt","local_path":"b.txt","sync_status":"sync_required"}]' \
		| jq . >".filesync/files.json"
	_out="$(filesync list files --status=synced 2>&1)" || die "list-files --status=synced"
	[[ "${_out}" == *a.txt* ]] || die "list-files --status=synced should list a.txt"
	[[ "${_out}" != *b.txt* ]] || die "list-files --status=synced should omit b.txt"
	[[ "${_out}" == *"Status summary (rows listed: 1): synced=1"* ]] \
		|| die "list-files summary should report synced=1"
)
