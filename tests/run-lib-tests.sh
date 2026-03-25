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
# shellcheck source=/dev/null
source "${ROOT}/lib/paths.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/files-append.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/json-state.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/deps.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/resolve.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/repo-resolve.sh"

if filesync_file_matches_fragment "" "a" "b"; then ok "empty fragment matches"; else bad "empty fragment"; fi
if filesync_file_matches_fragment "foo" "x/foo" "y"; then ok "fragment in local_path"; else bad "local_path match"; fi
if filesync_file_matches_fragment "bar" "a" "z/bar/b"; then ok "fragment in repo_file_path"; else bad "repo_path match"; fi
if ! filesync_file_matches_fragment "zzz" "a" "b"; then ok "non-match"; else bad "should not match"; fi

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

pe="$(file_sync_parse_to_epoch "")"
if [[ "${pe}" == "0" ]]; then ok "parse_to_epoch empty"; else bad "empty epoch got ${pe}"; fi
pe="$(file_sync_parse_to_epoch "null")"
if [[ "${pe}" == "0" ]]; then ok "parse_to_epoch null"; else bad "null epoch got ${pe}"; fi
pe="$(file_sync_parse_to_epoch "2020-01-01T00:00:00Z")"
if [[ "${pe}" =~ ^[0-9]+$ ]] && [[ "${pe}" -gt 1000000000 ]]; then ok "parse_to_epoch iso"; else bad "iso epoch got ${pe}"; fi

iso0="$(file_sync_epoch_to_iso 0)"
if [[ "${iso0}" == 1970-01-01* ]]; then ok "epoch_to_iso unix epoch"; else bad "epoch_to_iso got ${iso0}"; fi

for _st in synced sync_required local_newer conflict detached error_x unknown; do
	if [[ "$(file_sync_status_color "${_st}")" != *$'\033'* ]]; then bad "status_color ${_st}"; break; fi
done
[[ "${fail}" -eq 0 ]] && ok "status_color variants emit ansi"
if [[ "$(file_sync_color_reset)" == *$'\033[0m'* ]]; then ok "color_reset"; else bad "color_reset"; fi

filesync_require_jq && ok "require_jq" || bad "require_jq"
filesync_require_git && ok "require_git" || bad "require_git"
nowe="$(file_sync_now_epoch)"
if [[ "${nowe}" =~ ^[0-9]+$ ]]; then ok "now_epoch"; else bad "now_epoch ${nowe}"; fi
if [[ "$(file_sync_now_iso)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then ok "now_iso"; else bad "now_iso"; fi

if filesync_marker_style_valid "html" && ! filesync_marker_style_valid "nope"; then ok "marker_style_valid"; else bad "marker_style_valid"; fi
if [[ "$(filesync_marker_style_for_path "x.css")" == "block_c" ]]; then ok "marker_style css"; else bad "css style"; fi
if [[ "$(filesync_marker_style_for_path "q.sql")" == "line_dash" ]]; then ok "marker_style sql"; else bad "sql style"; fi
if [[ "$(filesync_marker_style_for_path "a.js")" == "line_slash" ]]; then ok "marker_style js"; else bad "js style"; fi
if [[ "$(filesync_marker_style_for_path "unknown.bin")" == "line_hash" ]]; then ok "marker_style default hash"; else bad "default style"; fi
if [[ "$(filesync_marker_style_resolve "x.css" "bogus")" == "block_c" ]]; then ok "marker_style_resolve invalid override"; else bad "invalid override"; fi
if [[ "$(filesync_marker_style_resolve "x.py" "line_slash")" == "line_slash" ]]; then ok "marker_style_resolve override"; else bad "override"; fi

if filesync_marker_parse_line "# filesync:sync kind=master path=p"; then
	if [[ "${FILESYNC_M_STYLE}" == "line_hash" && "${FILESYNC_M_INNER}" == *kind=master* ]]; then
		ok "marker_parse_line hash"
	else
		bad "marker_parse_line hash style/inner"
	fi
else
	bad "marker_parse_line hash failed"
fi
if filesync_marker_parse_line '<!-- filesync:sync kind=clone repo=r -->'; then
	if [[ "${FILESYNC_M_STYLE}" == "html" ]]; then ok "marker_parse_line html"; else bad "html style ${FILESYNC_M_STYLE}"; fi
else
	bad "marker_parse_line html failed"
fi
if filesync_marker_parse_line '/* filesync:sync kind=master */'; then
	if [[ "${FILESYNC_M_STYLE}" == "block_c" ]]; then ok "marker_parse_line block_c"; else bad "block_c style ${FILESYNC_M_STYLE}"; fi
else
	bad "marker_parse_line block_c failed"
fi
if filesync_marker_parse_line '// filesync:sync kind=clone'; then
	if [[ "${FILESYNC_M_STYLE}" == "line_slash" ]]; then ok "marker_parse_line line_slash"; else bad "line_slash style ${FILESYNC_M_STYLE}"; fi
else
	bad "marker_parse_line line_slash failed"
fi
if filesync_marker_parse_line '-- filesync:sync kind=clone'; then
	if [[ "${FILESYNC_M_STYLE}" == "line_dash" ]]; then ok "marker_parse_line line_dash"; else bad "line_dash style ${FILESYNC_M_STYLE}"; fi
else
	bad "marker_parse_line line_dash failed"
fi

fmt="$(filesync_marker_format_line "line_slash" "filesync:sync kind=x")"
if [[ "${fmt}" == "// filesync:sync kind=x" ]]; then ok "marker_format_line slash"; else bad "format slash"; fi
fmt="$(filesync_marker_format_line "line_hash" "inner")"
if [[ "${fmt}" == "# inner" ]]; then ok "marker_format_line hash"; else bad "format hash"; fi
fmt="$(filesync_marker_format_line "line_dash" "inner")"
if [[ "${fmt}" == "-- inner" ]]; then ok "marker_format_line dash"; else bad "format dash"; fi
fmt="$(filesync_marker_format_line "block_c" "inner")"
if [[ "${fmt}" == "/* inner */" ]]; then ok "marker_format_line block_c"; else bad "format block_c"; fi
fmt="$(filesync_marker_format_line "html" "inner")"
if [[ "${fmt}" == "<!-- inner -->" ]]; then ok "marker_format_line html"; else bad "format html"; fi
fmt="$(filesync_marker_format_line "bogus" "inner")"
if [[ "${fmt}" == "# inner" ]]; then ok "marker_format_line fallback hash"; else bad "format fallback"; fi

td="$(mktemp -d)"
trap 'rm -rf "${td}"' EXIT

proj="${td}/walkproj"
mkdir -p "${proj}/.filesync"
printf '%s\n' '[]' >"${proj}/.filesync/repos.json"
printf '%s\n' '[]' >"${proj}/.filesync/files.json"
if (
	cd "${proj}"
	unset FILESYNC_PROJECT_ROOT FILESYNC_DIR
	filesync_resolve_or_exit && [[ "${PROJECT_ROOT}" == "${proj}" ]]
); then ok "resolve_or_exit finds walk-up .filesync"; else bad "resolve_or_exit walk-up"; fi

if (
	cd "$(mktemp -d)"
	unset FILESYNC_PROJECT_ROOT FILESYNC_DIR
	filesync_resolve_or_exit 2>/dev/null
); then bad "resolve_or_exit should fail without .filesync"; else ok "resolve_or_exit fails without .filesync"; fi

mkdir -p "${td}/absrepo/existing"
rp="$(filesync_resolve_repo_path "${td}/absrepo" "${td}/absrepo/existing" "absolute")"
if [[ -n "${rp}" && "${rp}" == "$(cd "${td}/absrepo/existing" && pwd -P)" ]]; then ok "resolve_repo_path absolute"; else bad "absolute path got ${rp}"; fi
empt="$(filesync_resolve_repo_path "${td}/absrepo" "" "absolute" 2>/dev/null || true)"
if [[ -z "${empt}" ]]; then ok "resolve_repo_path empty"; else bad "empty got ${empt}"; fi

mkdir -p "${td}/relproj/subdir"
relout="$(filesync_resolve_repo_path "${td}/relproj" "subdir" "relative")"
if [[ "${relout}" == "$(cd "${td}/relproj/subdir" && pwd -P)" ]]; then ok "resolve_repo_path relative"; else bad "relative got ${relout}"; fi

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

if (
	_rf="${td}/reqfiles/.filesync"
	mkdir -p "${_rf}"
	printf '%s\n' '[]' >"${_rf}/files.json"
	export FILESYNC_DIR="${_rf}"
	filesync_require_files 2>/dev/null
); then bad "require_files should fail without repos.json"; else ok "require_files missing repos"; fi

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

printf '%s\n' '[{"name":"r1","path":"repodir","url":"","branch":"main"}]' >"${td}/repos.json"
printf '%s\n' '[]' >"${td}/files.json"
entry='{"local_path":"tools/x.txt","repo_name":"r1","repo_file_path":"tools/x.txt","sync_status":"synced"}'
if filesync_files_append_entry "${td}/files.json" "${td}/repos.json" "r1" "${entry}" && [[ "$(jq 'length' "${td}/files.json")" -eq 1 ]]; then
	ok "files_append_entry"
else
	bad "files_append_entry"
fi
if filesync_files_append_entry "${td}/files.json" "${td}/repos.json" "r1" "${entry}" 2>/dev/null; then
	bad "files_append duplicate should fail"
else
	ok "files_append rejects duplicate local_path"
fi
if filesync_files_append_entry "${td}/files.json" "${td}/repos.json" "missing" "${entry}" 2>/dev/null; then
	bad "files_append missing repo should fail"
else
	ok "files_append rejects unknown repo"
fi

declare -A FILESYNC_REPO_DIR_CACHE
declare -a FILESYNC_CLONED_TEMP_DIRS
jq -n --slurpfile s "${td}/assembled.json" '$s[0] * {repos: [{name: "origin", path: "repodir", url: null, branch: "main"}]}' >"${td}/state_repos.json"
mkdir -p "${PROJECT_ROOT}/repodir"
CONFIG_FILE="${td}/state_repos.json"
PATH_MODE="relative"
export CONFIG_FILE PROJECT_ROOT PATH_MODE
info="$(filesync_get_repo_info "origin")"
if [[ "${info}" == repodir\|* ]]; then ok "get_repo_info"; else bad "get_repo_info got ${info}"; fi
rd="$(filesync_get_repo_dir "origin")"
if [[ "${rd}" == "$(cd "${PROJECT_ROOT}/repodir" && pwd -P)" ]]; then ok "get_repo_dir existing path"; else bad "get_repo_dir got ${rd}"; fi
rd2="$(filesync_get_repo_dir "origin")"
if [[ "${rd2}" == "${rd}" ]]; then ok "get_repo_dir cache"; else bad "cache"; fi

touch "${td}/mtime_target"
me="$(file_sync_mtime_epoch "${td}/mtime_target")"
if [[ "${me}" =~ ^[0-9]+$ ]]; then ok "mtime_epoch"; else bad "mtime_epoch ${me}"; fi
mis="$(file_sync_mtime_iso "${td}/mtime_target")"
if [[ "${mis}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then ok "mtime_iso"; else bad "mtime_iso ${mis}"; fi

rows_path="${td}/files_row.json"
printf '%s\n' '[{"local_path":"f.txt","sync_status":"synced","repo_name":"origin"}]' >"${rows_path}"
touch "${td}/master_f.txt" "${PROJECT_ROOT}/f.txt"
filesync_write_file_row "${rows_path}" "${PROJECT_ROOT}" "f.txt" "${td}/master_f.txt" "synced"
if jq -e '.[] | select(.local_path=="f.txt") | .last_sync_at and .repo_file_modified_at and .local_file_modified_at' "${rows_path}" >/dev/null; then
	ok "write_file_row"
else
	bad "write_file_row"
fi

mf="${td}/m.txt"
echo "x" >"${mf}"
echo "# filesync:sync kind=clone path=tools/x repo=origin" >>"${mf}"
out="${td}/out.txt"
if render_master_marker_file "${mf}" "${out}"; then
	if grep -qE 'filesync:sync kind=master([[:space:]]|$)' "${out}"; then
		ok "render_master_marker_file (from clone)"
	else
		bad "master marker output"
	fi
else
	bad "render_master_marker_file failed"
fi

echo "# filesync:sync kind=master path=z" >"${mf}"
if render_master_marker_file "${mf}" "${out}" && cmp -s "${mf}" "${out}"; then
	ok "render_master_marker_file (already master copies)"
else
	bad "render master copy"
fi

clone_out="${td}/clone_out.txt"
if render_clone_from_master_file "${mf}" "p/r" "origin" "${clone_out}" && grep -qE 'kind=clone' "${clone_out}" && grep -q 'path=p/r' "${clone_out}"; then
	ok "render_clone_from_master_file"
else
	bad "render_clone_from_master_file"
fi

det_out="${td}/det_out.txt"
echo "// filesync:sync kind=clone path=a repo=b" >"${mf}"
if render_detached_marker_file "${mf}" "${det_out}" "a" "b" && grep -qE 'kind=detached' "${det_out}"; then
	ok "render_detached_marker_file"
else
	bad "render_detached_marker_file"
fi

xf="${td}/transform.txt"
echo "before" >"${xf}"
echo "# filesync:sync kind=master" >>"${xf}"
echo "after" >>"${xf}"
tout="${td}/transform.out.txt"
if filesync_marker_transform_file "${xf}" "${tout}" "filesync:sync kind=clone path=x repo=y" "${xf}" && grep -q 'kind=clone path=x' "${tout}"; then
	ok "marker_transform_file"
else
	bad "marker_transform_file"
fi

echo "# filesync:sync kind=master" >"${mf}"
if has_any_file_sync_marker "${mf}" && has_master_file_sync_marker "${mf}" && ! has_clone_file_sync_marker "${mf}"; then ok "has_any / has_master / not clone"; else bad "has_any/has_master"; fi
echo "# filesync:sync kind=clone detached=true" >"${mf}"
if has_detached_clone_file_sync_marker "${mf}" && has_clone_file_sync_marker "${mf}"; then ok "has_detached_clone"; else bad "has_detached_clone"; fi

echo "# filesync:sync kind=clone repo=r" >"${mf}"
if replace_clone_with_detached_marker "${mf}" && grep -q 'detached=true' "${mf}" && grep -qE 'kind=clone' "${mf}"; then
	ok "replace_clone_with_detached_marker"
else
	bad "replace_clone_with_detached_marker"
fi

unset FILESYNC_M_STYLE
if [[ "$(filesync_marker_effective_style "x.js" "")" == "line_slash" ]]; then ok "marker_effective_style from path"; else bad "effective_style path"; fi
if filesync_marker_parse_line "# filesync:sync kind=x"; then
	est="$(filesync_marker_effective_style "x.js" "")"
	if [[ "${est}" == "line_hash" ]]; then ok "marker_effective_style from parse"; else bad "effective_style parse got ${est}"; fi
else
	bad "parse for effective_style"
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
strip2="${td}/strip2.txt"
strip_filesync_marker_lines "${mf}" "${strip2}"
if ! grep -q 'filesync:sync' "${strip2}"; then ok "strip_filesync_marker_lines alias"; else bad "strip alias"; fi

if [[ "${fail}" -ne 0 ]]; then
	echo "run-lib-tests.sh: failures" >&2
	exit 1
fi
echo "run-lib-tests.sh: all passed."
