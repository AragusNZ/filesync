#!/usr/bin/env bash
# Pure library checks (no staged install). Args: REPO_ROOT
set -euo pipefail

ROOT="${1:?repo root}"
fail=0
ok() { echo "  lib ok: $*"; }
bad() {
	echo "  lib FAIL: $*" >&2
	fail=1
}

# shellcheck source=/dev/null
source "${ROOT}/lib/data-names.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/file-filter.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/status.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/markers.sh"

if filesync_file_matches_fragment "" "a" "b"; then ok "empty fragment matches"; else bad "empty fragment"; fi
if filesync_file_matches_fragment "foo" "x/foo" "y"; then ok "fragment in local_path"; else bad "local_path match"; fi
if ! filesync_file_matches_fragment "zzz" "a" "b"; then ok "non-match"; else bad "should not match"; fi

st="$(file_sync_compute_status 1 100 100 100 100)"
if [[ "${st}" == "synced" ]]; then ok "compute_status synced"; else bad "synced got ${st}"; fi

st="$(file_sync_compute_status 0 200 100 0 200)"
if [[ "${st}" == "sync_required" ]]; then ok "compute_status sync_required"; else bad "sync_required got ${st}"; fi

td="$(mktemp -d)"
trap 'rm -rf "${td}"' EXIT
export FILESYNC_PKG_ROOT="${ROOT}"
export FILESYNC_DIR="${td}"
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

mf="${td}/m.txt"
echo "x" >"${mf}"
echo "# filesync:sync kind=clone path=tools/x repo=origin" >>"${mf}"
out="${td}/out.txt"
if render_master_marker_file "${mf}" "${out}"; then
	if grep -qE 'filesync:sync kind=master([[:space:]]|$)' "${out}"; then
		ok "render_master_marker_file"
	else
		bad "master marker output"
	fi
else
	bad "render_master_marker_file failed"
fi

strip="${td}/strip.txt"
{
	echo "keep"
	echo "# filesync:sync kind=master"
	echo "tail"
} >"${mf}"
strip_file_sync_marker_lines "${mf}" "${strip}"
if grep -q 'filesync:sync' "${strip}"; then
	bad "strip markers left marker"
else
	ok "strip_file_sync_marker_lines"
fi

style="$(filesync_marker_style_for_path "foo.vue")"
if [[ "${style}" == "html" ]]; then ok "marker_style vue"; else bad "vue style got ${style}"; fi

if [[ "$(filesync_marker_style_resolve "x.py" "line_slash")" == "line_slash" ]]; then ok "marker_style_resolve override"; else bad "override"; fi

if [[ "${fail}" -ne 0 ]]; then
	echo "run-lib-tests.sh: failures" >&2
	exit 1
fi
echo "run-lib-tests.sh: all passed."
