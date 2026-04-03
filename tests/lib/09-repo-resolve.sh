#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/paths.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/repo-resolve.sh"

td="${LIB_TEST_TMP}"
PROJECT_ROOT="${td}/stproj"
mkdir -p "${PROJECT_ROOT}/repodir"
REPO_PATH_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
jq -n \
  --arg rroot "$REPO_PATH_ROOT" \
  '{repos: [{name: "origin", path: "repodir", url: null, branch: "main", merge_using_git: false}], files: [], repo_path_root: $rroot, progress_display: "percent"}' >"${td}/state_repos.json"
# shellcheck disable=SC2034
declare -A FILESYNC_REPO_DIR_CACHE
# shellcheck disable=SC2034
declare -a FILESYNC_CLONED_TEMP_DIRS
CONFIG_FILE="${td}/state_repos.json"
export CONFIG_FILE REPO_PATH_ROOT
info="$(filesync_get_repo_info "origin")"
if [[ "${info}" == repodir\|* ]]; then ok "get_repo_info"; else bad "get_repo_info got ${info}"; fi
rd="$(filesync_get_repo_dir "origin")"
if [[ "${rd}" == "$(cd "${PROJECT_ROOT}/repodir" && pwd -P)" ]]; then ok "get_repo_dir existing path"; else bad "get_repo_dir got ${rd}"; fi
rd2="$(filesync_get_repo_dir "origin")"
if [[ "${rd2}" == "${rd}" ]]; then ok "get_repo_dir cache"; else bad "cache"; fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
