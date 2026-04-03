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
export FILESYNC_SYSTEM_HOME="${td}/prefhome"
mkdir -p "${FILESYNC_SYSTEM_HOME}"
echo '{"progress_display":"bar"}' | jq . >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"
# shellcheck source=/dev/null
source "${ROOT}/lib/preferences-merge.sh"
merged="$(filesync_merged_preferences)"
if echo "${merged}" | jq -e '.progress_display == "bar"' >/dev/null; then
	ok "merged preferences user overrides default"
else
	bad "merged preferences: ${merged}"
fi

export FILESYNC_SYSTEM_HOME="${td}/pref_strip"
mkdir -p "${FILESYNC_SYSTEM_HOME}"
echo '{"progress_display":"invalid","extra":1}' | jq . >"${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"
merged_strip="$(filesync_merged_preferences)"
if echo "${merged_strip}" | jq -e '.progress_display == "percent"' >/dev/null; then
	ok "merged preferences normalizes invalid progress_display"
else
	bad "merged preferences strip: ${merged_strip}"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
