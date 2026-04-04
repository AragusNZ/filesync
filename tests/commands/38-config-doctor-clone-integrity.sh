#!/usr/bin/env bash
# config doctor: clone markers vs files.json, orphans, json sanity.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

export FILESYNC_HOME="${TMP}/fsys-38-doc-clone"
rm -rf "$FILESYNC_HOME"

anchor="${TMP}/38-doc-clone-anchor"
repo="${anchor}/the-repo"
mkdir -p "${repo}/tools"
fixture="${TMP}/38-doc-clone-repos.json"
jq -n '[{name:"myrepo",path:"the-repo",url:null,branch:"main",id:"idr1",merge_using_git:false}]' >"$fixture"
filesync_test_seed_global_repos "$anchor" "$fixture" || die "seed"

(
	cd "$repo"
	filesync init --no-repo
)

# Wrong repo= in clone marker vs catalog
{
	printf '%s\n' '# filesync kind=clone path=tools/w.txt repo=wrongname repo_id=idr1'
	printf '%s\n' 'x'
} >"${repo}/tools/w.txt"
jq -n \
	--arg id "idr1" \
	'[{repo_id:$id,repo_file_path:"tools/w.txt",local_path:"tools/w.txt",sync_status:"synced"}]' \
	>"${repo}/.filesync/files.json"

(
	cd "$repo"
	out="$(filesync config doctor 2>&1)" || die "doctor"
	echo "$out" | grep -qF 'clone marker repo= does not match' || die "doctor should warn on repo= mismatch"
	echo "$out" | grep -qF 'Summary:' || die "summary"
)

# Fix marker; should not warn for repo mismatch on next doctor
{
	printf '%s\n' '# filesync kind=clone path=tools/w.txt repo=myrepo repo_id=idr1'
	printf '%s\n' 'x'
} >"${repo}/tools/w.txt"

(
	cd "$repo"
	out="$(filesync config doctor 2>&1)" || die "doctor"
	if echo "$out" | grep -qF 'clone marker repo= does not match'; then
		die "doctor should not warn when repo= matches catalog"
	fi
)

# Orphan clone marker (no row)
{
	printf '%s\n' '# filesync kind=clone path=tools/o.txt repo=myrepo repo_id=idr1'
	printf '%s\n' 'o'
} >"${repo}/tools/o.txt"

(
	cd "$repo"
	out="$(filesync config doctor 2>&1)" || die "doctor"
	echo "$out" | grep -qF 'no files.json row for local_path: tools/o.txt' || die "doctor should warn orphan clone"
)

# Unknown repo_id in files.json
jq -n \
	'[{repo_id:"unknown-id-xyz",repo_file_path:"tools/z.txt",local_path:"tools/z.txt",sync_status:"synced"}]' \
	>"${repo}/.filesync/files.json"
rm -f "${repo}/tools/o.txt" "${repo}/tools/w.txt"
: >"${repo}/tools/z.txt"

(
	cd "$repo"
	out="$(filesync config doctor 2>&1)" || die "doctor"
	echo "$out" | grep -qF 'unknown repo_id' || die "doctor should warn unknown repo_id"
	echo "$out" | grep -qF 'Skipping clone and master file scans' || die "doctor should skip scans when state fails to load"
)

# Duplicate local_path
jq -n \
	'[
    {repo_id:"idr1",repo_file_path:"a",local_path:"tools/dup.txt",sync_status:"synced"},
    {repo_id:"idr1",repo_file_path:"b",local_path:"tools/dup.txt",sync_status:"synced"}
  ]' >"${repo}/.filesync/files.json"
: >"${repo}/tools/dup.txt"

(
	cd "$repo"
	out="$(filesync config doctor 2>&1)" || die "doctor"
	echo "$out" | grep -qF 'duplicate local_path' || die "doctor should warn duplicate local_path"
)
