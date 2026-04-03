#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/re-proj"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	jq -n '[{"name":"r1","path":"../x","url":"u","branch":"main"}]' >"${TMP}/seed-09.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-09.json"
	filesync edit-repo r1 --path=../y
	jq -e '.[] | select(.name=="r1") | .path == "../y"' "${FILESYNC_HOME}/repos.json" >/dev/null || die "edit-repo --path"
)
