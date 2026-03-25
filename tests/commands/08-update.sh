#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

_uh="$(filesync update --help 2>&1)" || die "update --help"
[[ "${_uh}" == *GitHub* ]] || die "update --help body"
