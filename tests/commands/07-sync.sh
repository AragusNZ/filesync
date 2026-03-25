#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/sn-proj"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	printf '%s\n' '[]' | jq . >".filesync/repos.json"
	if filesync sync 2>/dev/null; then
		die "sync with zero repos should fail"
	fi
)
