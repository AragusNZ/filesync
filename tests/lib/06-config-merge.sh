#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/data-names.sh"

td="${LIB_TEST_TMP}"
export FILESYNC_PKG_ROOT="${ROOT}"
export FILESYNC_DIR="${td}/cfgdir"
mkdir -p "${FILESYNC_DIR}"
echo '{"path_mode":"absolute"}' >"${FILESYNC_DIR}/${FILESYNC_CONFIG_NAME}"
# shellcheck source=/dev/null
source "${ROOT}/lib/config-merge.sh"
merged="$(filesync_merged_top_level_config)"
if echo "${merged}" | jq -e '.path_mode == "absolute" and .file_sync_enabled == true' >/dev/null; then
	ok "merged config user overrides default"
else
	bad "merged config: ${merged}"
fi

export FILESYNC_DIR="${td}/cfg_enabled"
mkdir -p "${FILESYNC_DIR}"
echo '{"enabled":false}' >"${FILESYNC_DIR}/${FILESYNC_CONFIG_NAME}"
merged_en="$(filesync_merged_top_level_config)"
if echo "${merged_en}" | jq -e '.file_sync_enabled == false and (.enabled == null)' >/dev/null; then
	ok "merged config maps enabled to file_sync_enabled"
else
	bad "merged enabled alias: ${merged_en}"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
