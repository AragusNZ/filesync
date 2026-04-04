#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/mug-master"
proj="${TMP}/mug-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	touch .keep
	git add .keep
	git commit -q -m init
)
mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init --no-repo
	# shellcheck disable=SC2030,SC2031
	export FILESYNC_HOME="${TMP}/mug-filesync-home"
	mkdir -p "${FILESYNC_HOME}"
	jq -n '{version: 2}' >"${FILESYNC_HOME}/system.json"
	printf '%s\n' '[]' | jq . >"${FILESYNC_HOME}/collections.json"
	printf '%s\n' '{}' | jq . >"${FILESYNC_HOME}/preferences.json"
	rel="../$(basename "${master}")"
	jq -n \
		--arg p "$rel" \
		'[{"name":"origin","path":$p,"url":null,"branch":"main","id":"test-origin-id"}]' >"${FILESYNC_HOME}/repos.json"
	jq -e 'all(.[]; has("merge_using_git") | not)' "${FILESYNC_HOME}/repos.json" >/dev/null || die "fixture should omit merge_using_git"
	FILESYNC_REPO_PATH_ANCHOR="$(pwd)"
	export FILESYNC_REPO_PATH_ANCHOR
	printf '%s\n' '[]' >".filesync/files.json"
	filesync migrate >/dev/null || die "migrate should succeed"
	jq -e '.[] | select(.name == "origin") | (.merge_using_git | type) == "boolean"' "${FILESYNC_HOME}/repos.json" >/dev/null || die "migrate should set merge_using_git"
	jq -e '.[] | select(.name == "origin") | .merge_using_git == true' "${FILESYNC_HOME}/repos.json" >/dev/null || die "git checkout should get merge_using_git true"
)

# Non-git checkout path → migrate sets merge_using_git false.
plain="${TMP}/mug-plain-dir"
rm -rf "${plain}" "${TMP}/mug-proj-plain"
mkdir -p "${plain}" "${TMP}/mug-proj-plain"
(
	cd "${TMP}/mug-proj-plain"
	filesync init --no-repo
	# shellcheck disable=SC2030,SC2031
	export FILESYNC_HOME="${TMP}/mug-filesync-home-plain"
	mkdir -p "${FILESYNC_HOME}"
	jq -n '{version: 2}' >"${FILESYNC_HOME}/system.json"
	printf '%s\n' '[]' | jq . >"${FILESYNC_HOME}/collections.json"
	printf '%s\n' '{}' | jq . >"${FILESYNC_HOME}/preferences.json"
	jq -n \
		--arg p "../$(basename "${plain}")" \
		'[{"name":"plain","path":$p,"url":null,"branch":"main","id":"id-plain"}]' >"${FILESYNC_HOME}/repos.json"
	FILESYNC_REPO_PATH_ANCHOR="$(pwd)"
	export FILESYNC_REPO_PATH_ANCHOR
	printf '%s\n' '[]' >".filesync/files.json"
	filesync migrate >/dev/null || die "migrate plain should succeed"
	jq -e '.[] | select(.name == "plain") | .merge_using_git == false' "${FILESYNC_HOME}/repos.json" >/dev/null \
		|| die "non-git checkout should get merge_using_git false"
)
