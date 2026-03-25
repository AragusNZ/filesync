#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/data-names.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/config-merge.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/json-state.sh"

td="${LIB_TEST_TMP}"
export FILESYNC_PKG_ROOT="${ROOT}"
export PROJECT_ROOT="${td}/stproj"
export FILESYNC_DIR="${PROJECT_ROOT}/.filesync"
mkdir -p "${FILESYNC_DIR}"
printf '%s\n' '[]' >"${FILESYNC_DIR}/repos.json"
printf '%s\n' '[]' >"${FILESYNC_DIR}/files.json"
echo '{}' >"${FILESYNC_DIR}/config.json"
if filesync_assemble_state_to "${td}/assembled.json" && jq -e '.repos == [] and .files == [] and .path_mode' "${td}/assembled.json" >/dev/null; then
	ok "assemble_state_to"
else
	bad "assemble_state_to"
fi
printf '%s\n' '{}' >"${FILESYNC_DIR}/repos.json"
if filesync_assemble_state_to "${td}/bad.json" 2>/dev/null; then
	bad "assemble_state should reject non-array repos"
else
	ok "assemble_state rejects bad repos"
fi
printf '%s\n' '[]' >"${FILESYNC_DIR}/repos.json"

filesync_export_data_paths
if [[ "${FILESYNC_REPOS_FILE}" == "${FILESYNC_DIR}/repos.json" ]]; then ok "export_data_paths"; else bad "export_data_paths"; fi

export FILESYNC_USER_CONFIG="${FILESYNC_DIR}/touchcfg.json"
filesync_user_config_set_last_check_at "2021-06-15T12:00:00Z"
if jq -e '.last_check_at == "2021-06-15T12:00:00Z"' "${FILESYNC_USER_CONFIG}" >/dev/null; then
	ok "user_config_set_last_check_at create"
else
	bad "user_config create"
fi
filesync_user_config_set_last_check_at "2022-01-01T00:00:00Z"
if jq -e '.last_check_at == "2022-01-01T00:00:00Z"' "${FILESYNC_USER_CONFIG}" >/dev/null; then
	ok "user_config_set_last_check_at update"
else
	bad "user_config update"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
