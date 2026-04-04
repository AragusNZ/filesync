#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

# Basic: clone from master project into sibling; repo= inferred from global repos + target checkout
master="${TMP}/ac-master" proj_b="${TMP}/ac-proj-b"
rm -rf "${master}" "${proj_b}"
mkdir -p "${master}/tools" "${proj_b}"

(
	cd "${master}"
	filesync init
	{
		echo "BODY_X"
		echo "# filesync kind=master"
	} >tools/x.txt
)
jq -n \
	--arg p "${proj_b}" \
	'[{"name":"consumer","path":$p,"url":null,"branch":null}]' >"${TMP}/seed-22a.json"
filesync_test_seed_global_repos "${master}" "${TMP}/seed-22a.json"

(
	cd "${proj_b}"
	filesync init
)
jq -n \
	--arg p "${master}" \
	'[{"name":"source","path":$p,"url":null,"branch":null}]' >"${TMP}/seed-22b.json"
filesync_test_append_global_repos "${TMP}/seed-22b.json"

(
	cd "${master}"
	filesync add clone consumer tools/x.txt
	[[ -f "${proj_b}/tools/x.txt" ]] || die "target should have clone file"
	grep -qE 'filesync kind=clone' "${proj_b}/tools/x.txt" || die "clone marker"
	grep -qE 'path=tools/x\.txt' "${proj_b}/tools/x.txt" || die "clone path="
	grep -qE 'repo=source' "${proj_b}/tools/x.txt" || die "clone repo= inferred"
	jq -e '.[] | select(.local_path=="tools/x.txt") | .repo_id == "testid-source" and .repo_file_path == "tools/x.txt"' "${proj_b}/.filesync/files.json" >/dev/null \
		|| die "files.json row"
)

# Second add-clone same path should fail
(
	cd "${master}"
	set +e
	filesync add clone consumer tools/x.txt >/dev/null 2>&1
	_ec=$?
	set -e
	[[ "${_ec}" -ne 0 ]] || die "add-clone should fail when target file exists"
)

# Non-master marker on source should fail
echo "# filesync kind=clone path=x repo=y" >"${master}/tools/bad.txt"
(
	cd "${master}"
	set +e
	filesync add clone consumer tools/bad.txt >/dev/null 2>&1
	_ec=$?
	set -e
	[[ "${_ec}" -ne 0 ]] || die "add-clone should fail when source is not kind=master"
)

# Auto-prepend kind=master when no marker
echo "plain-only" >"${master}/tools/plain.txt"
(
	cd "${master}"
	filesync add clone consumer tools/plain.txt
	grep -qE 'kind=master' "${master}/tools/plain.txt" || die "auto master marker"
	grep -qE 'kind=clone' "${proj_b}/tools/plain.txt" || die "clone after auto master"
)

# :local_path override
{
	echo "OV"
	echo "# filesync kind=master"
} >"${master}/tools/w.txt"
(
	cd "${master}"
	filesync add clone consumer tools/w.txt:other/w.txt
	[[ -f "${proj_b}/other/w.txt" ]] || die "override local path"
	grep -qE 'path=tools/w\.txt' "${proj_b}/other/w.txt" || die "marker path= stays master path"
	jq -e '.[] | select(.local_path=="other/w.txt") | .repo_file_path == "tools/w.txt"' "${proj_b}/.filesync/files.json" >/dev/null || die "row paths"
)

# --also mirrors to second sibling
master2="${TMP}/ac-master2" pb="${TMP}/ac-pb" pc="${TMP}/ac-pc"
rm -rf "${master2}" "${pb}" "${pc}"
mkdir -p "${master2}/tools" "${pb}" "${pc}"

(
	cd "${master2}"
	filesync init
	{
		echo "ZED"
		echo "# filesync kind=master"
	} >tools/z.txt
)
jq -n \
	--arg b "${pb}" \
	--arg c "${pc}" \
	'[
		{"name":"pb","path":$b,"url":null,"branch":null},
		{"name":"pc","path":$c,"url":null,"branch":null}
	]' >"${TMP}/seed-22c.json"
filesync_test_seed_global_repos "${master2}" "${TMP}/seed-22c.json"
for d in "${pb}" "${pc}"; do
	(
		cd "${d}"
		filesync init
	)
done
jq -n \
	--arg m "${master2}" \
	'[{"name":"m","path":$m,"url":null,"branch":null}]' >"${TMP}/seed-22d.json"
filesync_test_append_global_repos "${TMP}/seed-22d.json"

(
	cd "${master2}"
	filesync add clone pb tools/z.txt --also=pc
	[[ -f "${pb}/tools/z.txt" && -f "${pc}/tools/z.txt" ]] || die "--also should write both"
	jq -e '.[] | select(.local_path=="tools/z.txt")' "${pb}/.filesync/files.json" >/dev/null || die "pb row"
	jq -e '.[] | select(.local_path=="tools/z.txt")' "${pc}/.filesync/files.json" >/dev/null || die "pc row"
)
