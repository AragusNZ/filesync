#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/init-norepo"
mkdir -p "${p}"
export FILESYNC_HOME="${TMP}/fsys-29-init"
rm -rf "${FILESYNC_HOME}"
(
	cd "${p}"
	filesync init --no-repo
)
[[ -f "${p}/.filesync/files.json" ]] || die "files.json missing"
[[ -f "${FILESYNC_HOME}/repos.json" ]] || die "repos.json missing"
[[ "$(jq 'length' "${FILESYNC_HOME}/repos.json")" -eq 0 ]] || die "init --no-repo should leave repos empty"
