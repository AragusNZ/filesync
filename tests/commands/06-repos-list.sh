#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/rl-proj"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	filesync list-repos >/dev/null || die "list-repos empty"
	filesync list-files >/dev/null || die "list-files empty"
	if filesync list-repos --repo=nosuchrepo 2>/dev/null; then
		die "list-repos --repo missing should fail"
	fi
	if filesync list-repos --file=x 2>/dev/null; then
		die "list-repos --file should fail"
	fi
	if ! filesync list-files --file=nomatch 2>/dev/null; then
		die "list-files --file with zero rows should succeed"
	fi
)
