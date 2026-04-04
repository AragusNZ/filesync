#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
unset NO_COLOR
# shellcheck source=/dev/null
source "${ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/status.sh"

st="$(file_sync_compute_status 1 100 100 100 100)"
if [[ "${st}" == "synced" ]]; then ok "compute_status synced"; else bad "synced got ${st}"; fi

st="$(file_sync_compute_status 0 200 100 0 200)"
if [[ "${st}" == "sync_required" ]]; then ok "compute_status sync_required (repo newer)"; else bad "sync_required got ${st}"; fi

st="$(file_sync_compute_status 0 100 300 0 200)"
if [[ "${st}" == "local_newer" ]]; then ok "compute_status local_newer"; else bad "local_newer got ${st}"; fi

st="$(file_sync_compute_status 0 300 300 100 400)"
if [[ "${st}" == "conflict" ]]; then ok "compute_status conflict"; else bad "conflict got ${st}"; fi

st="$(file_sync_compute_status 0 100 100 100 200)"
if [[ "${st}" == "sync_required" ]]; then ok "compute_status sync_required (tie diff_ok=0)"; else bad "tie diff_ok=0 got ${st}"; fi

# Identical content (diff_ok=1) but "now" older than repo mtime → not "synced"; check.sh
# refreshes now after clone so REPO_E does not exceed NOW_E spuriously.
st="$(file_sync_compute_status 1 200 100 0 150)"
if [[ "${st}" == "sync_required" ]]; then ok "compute_status sync_required (diff_ok=1 stale now)"; else bad "stale now got ${st}"; fi

pe="$(file_sync_parse_to_epoch "")"
if [[ "${pe}" == "0" ]]; then ok "parse_to_epoch empty"; else bad "empty epoch got ${pe}"; fi
pe="$(file_sync_parse_to_epoch "null")"
if [[ "${pe}" == "0" ]]; then ok "parse_to_epoch null"; else bad "null epoch got ${pe}"; fi
pe="$(file_sync_parse_to_epoch "2020-01-01T00:00:00Z")"
if [[ "${pe}" =~ ^[0-9]+$ ]] && [[ "${pe}" -gt 1000000000 ]]; then ok "parse_to_epoch iso"; else bad "iso epoch got ${pe}"; fi

iso0="$(file_sync_epoch_to_iso 0)"
if [[ "${iso0}" == 1970-01-01* ]]; then ok "epoch_to_iso unix epoch"; else bad "epoch_to_iso got ${iso0}"; fi

for _st in synced sync_required local_newer conflict detached error_x error_master_marker unknown; do
	if [[ "$(file_sync_status_color "${_st}")" != *$'\033'* ]]; then bad "status_color ${_st}"; break; fi
done
[[ "${fail}" -eq 0 ]] && ok "status_color variants emit ansi"
if [[ "$(file_sync_color_reset)" == *$'\033[0m'* ]]; then ok "color_reset"; else bad "color_reset"; fi

(
	export NO_COLOR=1
	# shellcheck source=/dev/null
	source "${ROOT}/lib/colors.sh"
	# shellcheck source=/dev/null
	source "${ROOT}/lib/status.sh"
	[[ "$(file_sync_status_color synced)" == "" ]] || exit 1
	[[ "$(file_sync_color_reset)" == "" ]] || exit 1
) || bad "NO_COLOR disables status ansi"
[[ "${fail}" -eq 0 ]] && ok "NO_COLOR disables status ansi"

nowe="$(file_sync_now_epoch)"
if [[ "${nowe}" =~ ^[0-9]+$ ]]; then ok "now_epoch"; else bad "now_epoch ${nowe}"; fi
if [[ "$(file_sync_now_iso)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then ok "now_iso"; else bad "now_iso"; fi

td="${LIB_TEST_TMP}"
touch "${td}/mtime_target"
me="$(file_sync_mtime_epoch "${td}/mtime_target")"
if [[ "${me}" =~ ^[0-9]+$ ]]; then ok "mtime_epoch"; else bad "mtime_epoch ${me}"; fi
mis="$(file_sync_mtime_iso "${td}/mtime_target")"
if [[ "${mis}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then ok "mtime_iso"; else bad "mtime_iso ${mis}"; fi

PROJECT_ROOT="${td}/stproj"
mkdir -p "${PROJECT_ROOT}"
rows_path="${td}/files_row.json"
printf '%s\n' '[{"local_path":"f.txt","sync_status":"synced","repo_id":"testid-origin"}]' >"${rows_path}"
touch "${td}/master_f.txt" "${PROJECT_ROOT}/f.txt"
filesync_write_file_row "${rows_path}" "${PROJECT_ROOT}" "f.txt" "${td}/master_f.txt" "synced"
if jq -e '.[] | select(.local_path=="f.txt") | .last_sync_at and .repo_file_modified_at and .local_file_modified_at' "${rows_path}" >/dev/null; then
	ok "write_file_row"
else
	bad "write_file_row"
fi

# --status CSV matching (sync / list files)
_m() { file_sync_status_matches_csv "$1" "$2" && echo y || echo n; }

[[ "$(_m "" "unset")" == y ]] || bad "csv unset matches empty"
[[ "$(_m "" "synced")" == n ]] || bad "csv synced does not match empty"
[[ "$(_m "synced" "synced")" == y ]] || bad "csv exact synced"
[[ "$(_m "synced" "unset,sync_required")" == n ]] || bad "csv no match"
[[ "$(_m "sync_required" "unset,sync_required")" == y ]] || bad "csv sync_required"
[[ "$(_m "detached" "all")" == n ]] || bad "all excludes detached"
_m3() { file_sync_status_matches_csv "$1" "$2" true && echo y || echo n; }
[[ "$(_m3 "detached" "all")" == y ]] || bad "all includes detached with include_detached"
[[ "$(_m "detached" "all,detached")" == y ]] || bad "all,detached lists detached explicitly"
[[ "$(_m "detached" "detached")" == y ]] || bad "detached literal token"
[[ "$(_m "synced" "all")" == y ]] || bad "all matches synced"
[[ "$(_m "error_x" "all")" == y ]] || bad "all matches error status"
[[ "$(_m "error_invalid_repo" "error")" == y ]] || bad "error matches error_*"
[[ "$(_m "synced" "error")" == n ]] || bad "error excludes non-error"
[[ "$(_m "detached" "error")" == n ]] || bad "error excludes detached"
[[ "${fail}" -eq 0 ]] && ok "status_matches_csv"

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
