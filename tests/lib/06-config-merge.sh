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
if echo "${merged}" | jq -e '.path_mode == "absolute" and .file_sync_enabled == true and .progress_display == "percent" and (has("show_progress") | not) and (has("enabled") | not)' >/dev/null; then
	ok "merged config user overrides default"
else
	bad "merged config: ${merged}"
fi

export FILESYNC_DIR="${td}/cfg_strip_keys"
mkdir -p "${FILESYNC_DIR}"
echo '{"show_progress":true,"enabled":false,"progress_display":"bar"}' >"${FILESYNC_DIR}/${FILESYNC_CONFIG_NAME}"
merged_strip="$(filesync_merged_top_level_config)"
if echo "${merged_strip}" | jq -e '.progress_display == "bar" and (has("show_progress") | not) and (has("enabled") | not)' >/dev/null; then
	ok "merged config drops obsolete show_progress and enabled keys"
else
	bad "merged strip keys: ${merged_strip}"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
