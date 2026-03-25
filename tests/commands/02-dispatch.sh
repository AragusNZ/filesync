#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

mkdir -p "${TMP}/dispatch-proj/dummy-repo"
(
	cd "${TMP}/dispatch-proj"
	filesync init
	jq -n '[{"name":"d","path":"dummy-repo","url":"u","branch":"main"}]' >".filesync/repos.json"
	if filesync not_a_real_subcommand_zz 2>/dev/null; then
		die "unknown subcommand should fail"
	fi
	_d="$(filesync --dry-run 2>&1)" || die "flag-first sync exit"
	[[ "${_d,,}" == *sync* ]] || die "flag-first should run sync"
)
