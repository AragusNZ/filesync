#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

# migrate must set repo_id on files.json rows from global repos.json name→id map.
proj="${TMP}/mrid-proj"
rm -rf "${proj}"
mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init --no-repo
	export FILESYNC_HOME="${TMP}/mrid-home"
	mkdir -p "${FILESYNC_HOME}"
	jq -n '{version: 2}' >"${FILESYNC_HOME}/system.json"
	printf '%s\n' '[]' | jq . >"${FILESYNC_HOME}/collections.json"
	printf '%s\n' '{}' | jq . >"${FILESYNC_HOME}/preferences.json"
	jq -n \
		'[{"name":"upstream","path":"../noop","url":null,"branch":"main","id":"uuid-upstream-1"}]' \
		>"${FILESYNC_HOME}/repos.json"
	export FILESYNC_REPO_PATH_ANCHOR="$(pwd)"
	jq -n \
		'[{
			repo_name: "upstream",
			local_path: "tools/x.txt",
			repo_file_path: "tools/x.txt",
			sync_status: "synced"
		}]' >".filesync/files.json"
	filesync migrate >/dev/null || die "migrate should succeed"
	jq -e '.[] | select(.local_path=="tools/x.txt") | .repo_id == "uuid-upstream-1"' \
		".filesync/files.json" >/dev/null || die "migrate should set repo_id from repo_name"
)
