#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/path-mode-proj"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	[[ "$(filesync path-mode)" == relative ]] || die "default path-mode show"
	filesync pm absolute
	[[ "$(filesync path-mode)" == absolute ]] || die "after set absolute"
	jq -e '.path_mode == "absolute"' .filesync/config.json >/dev/null || die "config json"
	filesync path-mode relative
	[[ "$(filesync path-mode)" == relative ]] || die "after set relative"
	if filesync path-mode bogus 2>/dev/null; then
		die "invalid path_mode should fail"
	fi
	if filesync path-mode --nope 2>/dev/null; then
		die "unknown flag should fail"
	fi
)
