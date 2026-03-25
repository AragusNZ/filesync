#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/env-root"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
)
mkdir -p "${TMP}/outside"
(
	cd "${TMP}/outside"
	FILESYNC_PROJECT_ROOT="${p}" filesync check >/dev/null || die "FILESYNC_PROJECT_ROOT check"
)
