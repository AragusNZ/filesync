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
	filesync repos >/dev/null || die "repos empty"
	filesync list >/dev/null || die "list empty"
	if filesync repos --repo=nosuchrepo 2>/dev/null; then
		die "repos --repo missing should fail"
	fi
	if filesync repos --file=x 2>/dev/null; then
		die "repos --file should fail"
	fi
	if ! filesync list --file=nomatch 2>/dev/null; then
		die "list --file with zero rows should succeed"
	fi
)
