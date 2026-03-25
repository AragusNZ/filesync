#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/init-edges"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	if filesync init 2>/dev/null; then
		die "init twice should fail"
	fi
)
rm -f "${p}/.filesync/files.json"
(
	cd "${p}"
	filesync init
	[[ -f "${p}/.filesync/files.json" ]] || die "init should restore missing files.json"
)
