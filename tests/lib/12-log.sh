#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/log.sh"

msg="$(filesync_error "log test marker" 2>&1 || true)"
if [[ "${msg}" == *filesync:* && "${msg}" == *"log test marker"* ]]; then
	ok "filesync_error prefixes and message"
else
	bad "filesync_error output: ${msg}"
fi

msgw="$(filesync_warn "warn marker" 2>&1 || true)"
if [[ "${msgw}" == *filesync:* && "${msgw}" == *"warn marker"* ]]; then
	ok "filesync_warn prefixes and message"
else
	bad "filesync_warn output: ${msgw}"
fi

unset FILESYNC_VERBOSE
msgi="$(filesync_info "silent info" 2>&1 || true)"
if [[ -z "${msgi}" ]]; then
	ok "filesync_info quiet without FILESYNC_VERBOSE"
else
	bad "filesync_info should be quiet: ${msgi}"
fi

export FILESYNC_VERBOSE=1
msgiv="$(filesync_info "verbose info" 2>&1 || true)"
if [[ "${msgiv}" == *filesync:* && "${msgiv}" == *"verbose info"* ]]; then
	ok "filesync_info with FILESYNC_VERBOSE"
else
	bad "filesync_info verbose: ${msgiv}"
fi

(
	export NO_COLOR=1
	# shellcheck source=/dev/null
	source "${ROOT}/lib/colors.sh"
	# shellcheck source=/dev/null
	source "${ROOT}/lib/log.sh"
	_mnc="$(filesync_error "no color marker" 2>&1 || true)"
	[[ "${_mnc}" == *$'\033'* ]] && exit 1
	[[ "${_mnc}" == *filesync:* ]] || exit 1
) || bad "filesync_error respects NO_COLOR"
[[ "${fail}" -eq 0 ]] && ok "filesync_error respects NO_COLOR"

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
