#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
# shellcheck source=/dev/null
source "${ROOT}/lib/resolve.sh"

td="${LIB_TEST_TMP}"
proj="${td}/walkproj"
mkdir -p "${proj}/.filesync"
printf '%s\n' '[]' >"${proj}/.filesync/repos.json"
printf '%s\n' '[]' >"${proj}/.filesync/files.json"
if (
	cd "${proj}"
	unset FILESYNC_PROJECT_ROOT FILESYNC_DIR
	filesync_resolve_or_exit && [[ "${PROJECT_ROOT}" == "${proj}" ]]
); then ok "resolve_or_exit finds walk-up .filesync"; else bad "resolve_or_exit walk-up"; fi

if (
	cd "$(mktemp -d)"
	unset FILESYNC_PROJECT_ROOT FILESYNC_DIR
	filesync_resolve_or_exit 2>/dev/null
); then bad "resolve_or_exit should fail without .filesync"; else ok "resolve_or_exit fails without .filesync"; fi

if (
	_rf="${td}/reqfiles/.filesync"
	mkdir -p "${_rf}"
	printf '%s\n' '[]' >"${_rf}/files.json"
	export FILESYNC_DIR="${_rf}"
	filesync_require_files 2>/dev/null
); then bad "require_files should fail without repos.json"; else ok "require_files missing repos"; fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
