#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/ed-proj"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	filesync disable
	filesync check >/dev/null || die "check when disabled"
	filesync sync >/dev/null || die "sync when disabled"
	printf '%s\n' y | filesync enable
	filesync check >/dev/null || die "check after enable"
)
