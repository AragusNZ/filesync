#!/usr/bin/env bash
# Legacy global repos.json without merge_using_git is repaired on first catalog command; new repo + check work.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/grr-master"
proj="${TMP}/grr-proj"
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
	# shellcheck disable=SC2030,SC2031
	export FILESYNC_HOME="${TMP}/grr-filesync-home"
	rm -rf "${FILESYNC_HOME}"
	filesync init --no-repo
	jq -n \
		--arg p "../$(basename "${master}")" \
		'[{"name":"legacy","path":$p,"url":"https://example.com/legacy.git","branch":"main","id":"id-legacy"}]' \
		>"${FILESYNC_HOME}/repos.json"
	jq -e 'all(.[]; has("merge_using_git") | not)' "${FILESYNC_HOME}/repos.json" >/dev/null || die "fixture must omit merge_using_git"
	FILESYNC_REPO_PATH_ANCHOR="$(pwd)"
	export FILESYNC_REPO_PATH_ANCHOR
	printf '%s\n' 'newrepo' '' 'https://example.com/new.git' 'main' | filesync new repo
	jq -e 'all(.[]; (.merge_using_git | type) == "boolean")' "${FILESYNC_HOME}/repos.json" >/dev/null \
		|| die "all repos must have boolean merge_using_git after new repo"
	jq -e '.[] | select(.name == "legacy") | .merge_using_git == true' "${FILESYNC_HOME}/repos.json" >/dev/null \
		|| die "legacy git checkout should get merge_using_git true"
	jq -e '.[] | select(.name == "newrepo") | .merge_using_git == false' "${FILESYNC_HOME}/repos.json" >/dev/null \
		|| die "newrepo registered from non-git cwd should get merge_using_git false"
	filesync check >/dev/null || die "check should succeed after catalog repair"
)
