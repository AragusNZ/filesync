#!/usr/bin/env bash
# doctor inspect: project scan for kind=master with no catalog clones.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

export FILESYNC_HOME="${TMP}/fsys-37-doc-mm"
rm -rf "$FILESYNC_HOME"

anchor="${TMP}/37-doc-mm-anchor"
repo="${anchor}/the-repo"
mkdir -p "${repo}/tools"
{
	printf '%s\n' '# filesync kind=master'
	printf '%s\n' 'body'
} >"${repo}/tools/m.txt"

fixture="${TMP}/37-doc-mm-repos.json"
jq -n '[{name:"myrepo",path:"the-repo",url:null,branch:"main",id:"idr1",merge_using_git:false}]' >"$fixture"

filesync_test_seed_global_repos "$anchor" "$fixture" || die "seed global repos"

(
	cd "$repo"
	filesync init --no-repo
)

(
	cd "$repo"
	out="$(filesync doctor 2>&1)" || die "doctor should exit 0"
	echo "$out" | grep -qF 'kind=master with no tracked clones' || die "doctor should warn when master has no rows"
	echo "$out" | grep -qF 'Summary:' || die "doctor should print summary"
)

jq -n \
	--arg id "idr1" \
	'[{repo_id:$id,repo_file_path:"tools/m.txt",local_path:"tools/m.txt",sync_status:"synced"}]' \
	>"${repo}/.filesync/files.json"

(
	cd "$repo"
	out="$(filesync doctor inspect 2>&1)" || die "doctor inspect should exit 0"
	if echo "$out" | grep -qF 'kind=master with no tracked clones'; then
		die "doctor should not warn when a clone row exists"
	fi
)

nop="${TMP}/37-doc-mm-noproject"
mkdir -p "$nop"
(
	cd "$nop"
	out="$(filesync doctor 2>&1)" || die "doctor should exit 0"
	echo "$out" | grep -qF 'Skipping project-local scans' || die "doctor should skip scan outside a project"
	echo "$out" | grep -qF 'Summary:' || die "doctor should print summary line"
)
