#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/markers.sh"

td="${LIB_TEST_TMP}"

if filesync_marker_parse_line "# filesync kind=master path=p"; then
	if [[ "${FILESYNC_M_STYLE}" == "line_hash" && "${FILESYNC_M_INNER}" == *kind=master* ]]; then
		ok "marker_parse_line hash"
	else
		bad "marker_parse_line hash style/inner"
	fi
else
	bad "marker_parse_line hash failed"
fi
if filesync_marker_parse_line '<!-- filesync kind=clone repo=r -->'; then
	if [[ "${FILESYNC_M_STYLE}" == "html" ]]; then ok "marker_parse_line html"; else bad "html style ${FILESYNC_M_STYLE}"; fi
else
	bad "marker_parse_line html failed"
fi
if filesync_marker_parse_line '/* filesync kind=master */'; then
	if [[ "${FILESYNC_M_STYLE}" == "block_c" ]]; then ok "marker_parse_line block_c"; else bad "block_c style ${FILESYNC_M_STYLE}"; fi
else
	bad "marker_parse_line block_c failed"
fi
if filesync_marker_parse_line '// filesync kind=clone'; then
	if [[ "${FILESYNC_M_STYLE}" == "line_slash" ]]; then ok "marker_parse_line line_slash"; else bad "line_slash style ${FILESYNC_M_STYLE}"; fi
else
	bad "marker_parse_line line_slash failed"
fi
if filesync_marker_parse_line '-- filesync kind=clone'; then
	if [[ "${FILESYNC_M_STYLE}" == "line_dash" ]]; then ok "marker_parse_line line_dash"; else bad "line_dash style ${FILESYNC_M_STYLE}"; fi
else
	bad "marker_parse_line line_dash failed"
fi

fmt="$(filesync_marker_format_line "line_slash" "filesync kind=x")"
if [[ "${fmt}" == "// filesync kind=x" ]]; then ok "marker_format_line slash"; else bad "format slash"; fi
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

mf="${td}/m.txt"
echo "x" >"${mf}"
echo "# filesync kind=clone path=tools/x repo=origin" >>"${mf}"
out="${td}/out.txt"
if render_master_marker_file "${mf}" "${out}"; then
	if grep -qE 'filesync kind=master([[:space:]]|$)' "${out}"; then
		ok "render_master_marker_file (from clone)"
	else
		bad "master marker output"
	fi
else
	bad "render_master_marker_file failed"
fi

echo "# filesync kind=master path=z" >"${mf}"
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
echo "// filesync kind=clone path=a repo=b" >"${mf}"
if render_detached_marker_file "${mf}" "${det_out}" "a" "b" && grep -qE 'kind=detached' "${det_out}"; then
	ok "render_detached_marker_file"
else
	bad "render_detached_marker_file"
fi

xf="${td}/transform.txt"
echo "before" >"${xf}"
echo "# filesync kind=master" >>"${xf}"
echo "after" >>"${xf}"
tout="${td}/transform.out.txt"
if filesync_marker_transform_file "${xf}" "${tout}" "filesync kind=clone path=x repo=y" "${xf}" && grep -q 'kind=clone path=x' "${tout}"; then
	ok "marker_transform_file"
else
	bad "marker_transform_file"
fi

echo "# filesync kind=master" >"${mf}"
if has_any_file_sync_marker "${mf}" && has_master_file_sync_marker "${mf}" && ! has_clone_file_sync_marker "${mf}"; then ok "has_any / has_master / not clone"; else bad "has_any/has_master"; fi
echo "# filesync kind=clone detached=true" >"${mf}"
if has_detached_clone_file_sync_marker "${mf}" && has_clone_file_sync_marker "${mf}"; then ok "has_detached_clone"; else bad "has_detached_clone"; fi

echo "# filesync kind=clone repo=r" >"${mf}"
if replace_clone_with_detached_marker "${mf}" && grep -q 'detached=true' "${mf}" && grep -qE 'kind=clone' "${mf}"; then
	ok "replace_clone_with_detached_marker"
else
	bad "replace_clone_with_detached_marker"
fi

echo "# filesync kind=clone path=p repo=old" >"${mf}"
if filesync_marker_rename_repo_in_file "${mf}" "old" "new" && grep -qF 'repo=new' "${mf}" && ! grep -qF 'repo=old' "${mf}"; then
	ok "marker_rename_repo_in_file clone"
else
	bad "marker_rename_repo_in_file clone"
fi
echo "<!-- filesync kind=detached path=x repo=origin -->" >"${mf}"
if filesync_marker_rename_repo_in_file "${mf}" "origin" "upstream" && grep -qF 'repo=upstream' "${mf}"; then
	ok "marker_rename_repo_in_file html detached"
else
	bad "marker_rename_repo_in_file html"
fi
echo "# filesync kind=master" >"${mf}"
if filesync_marker_rename_repo_in_file "${mf}" "origin" "upstream"; then
	bad "marker_rename_repo_in_file should skip master"
else
	ok "marker_rename_repo_in_file skips master"
fi

unset FILESYNC_M_STYLE
if [[ "$(filesync_marker_effective_style "x.js" "")" == "line_slash" ]]; then ok "marker_effective_style from path"; else bad "effective_style path"; fi
if filesync_marker_parse_line "# filesync kind=x"; then
	est="$(filesync_marker_effective_style "x.js" "")"
	if [[ "${est}" == "line_hash" ]]; then ok "marker_effective_style from parse"; else bad "effective_style parse got ${est}"; fi
else
	bad "parse for effective_style"
fi

strip="${td}/strip.txt"
{
	echo "keep"
	echo "# filesync kind=master"
	echo "tail"
} >"${mf}"
strip_file_sync_marker_lines "${mf}" "${strip}"
if grep -q 'filesync' "${strip}"; then
	bad "strip markers left marker"
else
	ok "strip_file_sync_marker_lines"
fi
strip2="${td}/strip2.txt"
strip_filesync_marker_lines "${mf}" "${strip2}"
if ! grep -q 'filesync' "${strip2}"; then ok "strip_filesync_marker_lines alias"; else bad "strip alias"; fi

nm="${td}/non_master_strip.txt"
echo "# filesync kind=clone path=x repo=y" >"${td}/nm_in.txt"
echo "body" >>"${td}/nm_in.txt"
strip_non_master_filesync_marker_lines "${td}/nm_in.txt" "${nm}"
if [[ "$(tr -d '\n' <"${nm}")" == "body" ]]; then ok "strip_non_master removes clone"; else bad "strip_non_master clone"; fi
echo "# filesync kind=master" >"${td}/nm_m.txt"
echo "keep" >>"${td}/nm_m.txt"
strip_non_master_filesync_marker_lines "${td}/nm_m.txt" "${nm}"
if grep -qE 'kind=master' "${nm}" && grep -q 'keep' "${nm}" && ! grep -q 'kind=clone' "${nm}"; then
	ok "strip_non_master keeps master"
else
	bad "strip_non_master master"
fi

plain="${td}/plain.txt"
echo "body-only" >"${plain}"
if prepend_master_marker_to_file "${plain}" "x.txt" && head -1 "${plain}" | grep -qE 'kind=master' && grep -q 'body-only' "${plain}"; then
	ok "prepend_master_marker_to_file"
else
	bad "prepend_master_marker_to_file"
fi
if prepend_master_marker_to_file "${plain}" "x.txt"; then
	bad "prepend_master_marker_to_file should fail when marker exists"
else
	ok "prepend_master_marker_to_file rejects already marked"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
