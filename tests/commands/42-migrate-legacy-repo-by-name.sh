#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

# Legacy per-project repos.json: same repo name as global but different path — global wins, migrate succeeds.
proj="${TMP}/mlbn-proj"
rm -rf "${proj}"
mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init --no-repo
	export FILESYNC_HOME="${TMP}/mlbn-home"
	mkdir -p "${FILESYNC_HOME}"
	jq -n '{version: 2}' >"${FILESYNC_HOME}/system.json"
	printf '%s\n' '[]' | jq . >"${FILESYNC_HOME}/collections.json"
	printf '%s\n' '{}' | jq . >"${FILESYNC_HOME}/preferences.json"
	jq -n \
		'[{"name":"shared","path":"global-path","url":"https://example.com/a.git","branch":"main","id":"id-shared"}]' \
		>"${FILESYNC_HOME}/repos.json"
	FILESYNC_REPO_PATH_ANCHOR="$(pwd)"
	export FILESYNC_REPO_PATH_ANCHOR
	jq -n \
		'[{"name":"shared","path":"legacy-other-path","url":"https://example.com/b.git","branch":"develop"}]' \
		>".filesync/repos.json"
	printf '%s\n' '[]' >".filesync/files.json"
	out="$(filesync migrate 2>&1)" || die "migrate should succeed"
	echo "$out" | grep -q 'keeping global catalog entry' || die "expected notice when legacy differs"
	jq -e '.[] | select(.name=="shared") | .path == "global-path"' "${FILESYNC_HOME}/repos.json" >/dev/null \
		|| die "global path should be unchanged"
	jq -e '.[] | select(.name=="shared") | .url == "https://example.com/a.git"' "${FILESYNC_HOME}/repos.json" >/dev/null \
		|| die "global url should be unchanged"
	[[ ! -f ".filesync/repos.json" ]] || die "legacy repos.json should be removed"
)
