#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/paths.sh"

td="${LIB_TEST_TMP}"
mkdir -p "${td}/rroot/chk"
rr="${td}/rroot"
co="$(filesync_resolve_repo_checkout_dir "${rr}" "chk")"
if [[ "${co}" == "$(cd "${rr}/chk" && pwd -P)" ]]; then ok "resolve_repo_checkout_dir relative"; else bad "checkout dir got ${co}"; fi

mkdir -p "${td}/absabs"
ab="$(filesync_resolve_repo_checkout_dir "${td}/ignored" "${td}/absabs")"
if [[ "${ab}" == "$(cd "${td}/absabs" && pwd -P)" ]]; then ok "resolve_repo_checkout_dir absolute"; else bad "absolute got ${ab}"; fi

empt="$(filesync_resolve_repo_checkout_dir "${rr}" "" 2>/dev/null || true)"
if [[ -z "${empt}" ]]; then ok "resolve_repo_checkout_dir empty path"; else bad "empty got ${empt}"; fi

mkdir -p "${td}/rr2/nested/here"
pr="$(filesync_path_for_repos_json "${td}/rr2" "${td}/rr2/nested/here")"
if [[ "${pr}" == "nested/here" ]]; then ok "path_for_repos_json relative"; else bad "relative got ${pr}"; fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
