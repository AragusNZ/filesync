#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/git-repo-hints.sh"

td="${LIB_TEST_TMP}/git-hints"
rm -rf "${td}"
mkdir -p "${td}/repo"
git -C "${td}/repo" init -q
git -C "${td}/repo" config user.email "t@e.st"
git -C "${td}/repo" config user.name "t"
printf 'x\n' >"${td}/repo/f.txt"
git -C "${td}/repo" add f.txt
git -C "${td}/repo" commit -q -m m
git -C "${td}/repo" remote add origin "https://example.com/g/h.git"
git -C "${td}/repo" checkout -q -b mybranch

filesync_git_collect_hints "${td}/repo"
if [[ "${FILESYNC_GIT_HINT_TOP}" == "$(cd "${td}/repo" && pwd -P)" ]]; then ok "git hints top"; else bad "top got ${FILESYNC_GIT_HINT_TOP}"; fi
if [[ "${FILESYNC_GIT_HINT_URL}" == "https://example.com/g/h.git" ]]; then ok "git hints url"; else bad "url got ${FILESYNC_GIT_HINT_URL}"; fi
if [[ "${FILESYNC_GIT_HINT_BRANCH}" == "mybranch" ]]; then ok "git hints branch"; else bad "branch got ${FILESYNC_GIT_HINT_BRANCH}"; fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
