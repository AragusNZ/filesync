#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/paths.sh"

td="${LIB_TEST_TMP}"
mkdir -p "${td}/absrepo/existing"
rp="$(filesync_resolve_repo_path "${td}/absrepo" "${td}/absrepo/existing" "absolute")"
if [[ -n "${rp}" && "${rp}" == "$(cd "${td}/absrepo/existing" && pwd -P)" ]]; then ok "resolve_repo_path absolute"; else bad "absolute path got ${rp}"; fi
empt="$(filesync_resolve_repo_path "${td}/absrepo" "" "absolute" 2>/dev/null || true)"
if [[ -z "${empt}" ]]; then ok "resolve_repo_path empty"; else bad "empty got ${empt}"; fi

mkdir -p "${td}/relproj/subdir"
relout="$(filesync_resolve_repo_path "${td}/relproj" "subdir" "relative")"
if [[ "${relout}" == "$(cd "${td}/relproj/subdir" && pwd -P)" ]]; then ok "resolve_repo_path relative"; else bad "relative got ${relout}"; fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
