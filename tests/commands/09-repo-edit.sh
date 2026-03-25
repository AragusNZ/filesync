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
	jq -n '[{"name":"r1","path":"../x","url":"u","branch":"main"}]' >".filesync/repos.json"
	filesync edit-repo r1 --path=../y
	jq -e '.[] | select(.name=="r1") | .path == "../y"' ".filesync/repos.json" >/dev/null || die "edit-repo --path"
)
