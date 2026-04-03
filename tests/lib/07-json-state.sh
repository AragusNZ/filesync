#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=../../lib/data-names.sh
source "${ROOT}/lib/data-names.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/system-resolve.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/json-state.sh"

td="${LIB_TEST_TMP}"
export FILESYNC_PKG_ROOT="${ROOT}"
export FILESYNC_SYSTEM_HOME="${td}/syshome"
mkdir -p "${FILESYNC_SYSTEM_HOME}"
rr="${td}/reporoot"
mkdir -p "$rr"
FILESYNC_REPO_PATH_ANCHOR="$(cd "$rr" && pwd)"
export FILESYNC_REPO_PATH_ANCHOR
jq -n '{version: 2}' >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_SYSTEM_NAME}"
printf '%s\n' '[]' | jq . >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"
printf '%s\n' '[]' | jq . >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_COLLECTIONS_NAME}"
printf '%s\n' '{}' | jq . >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"

export PROJECT_ROOT="${td}/stproj"
export FILESYNC_DIR="${PROJECT_ROOT}/.filesync"
mkdir -p "${FILESYNC_DIR}"
printf '%s\n' '[]' | jq . >"${FILESYNC_DIR}/${FILESYNC_FILES_NAME}"

filesync_export_data_paths
if [[ "${FILESYNC_REPOS_FILE}" == "${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}" ]] && [[ "${FILESYNC_COLLECTIONS_FILE}" == "${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_COLLECTIONS_NAME}" ]]; then
	ok "export_data_paths"
else
	bad "export_data_paths"
fi

if filesync_assemble_state_to "${td}/assembled.json" && jq -e '.repos == [] and .files == [] and .progress_display == "percent" and .repo_path_root' "${td}/assembled.json" >/dev/null; then
	ok "assemble_state_to"
else
	bad "assemble_state_to"
fi

printf '%s\n' '{}' >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"
if filesync_assemble_state_to "${td}/bad.json" 2>/dev/null; then
	bad "assemble_state should reject non-array repos"
else
	ok "assemble_state rejects bad repos"
fi
printf '%s\n' '[]' | jq . >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"

jq -n '[{name:"x",id:"a",path:"p",url:null,branch:"main"},{name:"x",id:"b",path:"q",url:null,branch:"main"}]' >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"
if filesync_assemble_state_to "${td}/dup.json" 2>/dev/null; then
	bad "assemble_state should reject duplicate repo names"
else
	ok "assemble_state rejects duplicate repo names"
fi
printf '%s\n' '[]' | jq . >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"

printf '{ not-valid-json' >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"
_asm_err=""
if _asm_err=$(filesync_assemble_state_to "${td}/bad-merge.json" 2>&1); then
	bad "assemble_state should reject invalid preferences"
else
	if [[ "${_asm_err}" == *filesync:* ]]; then
		ok "assemble_state invalid preferences stderr"
	else
		bad "assemble_state invalid preferences missing filesync prefix: ${_asm_err}"
	fi
fi
printf '%s\n' '{}' | jq . >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
