#!/usr/bin/env bash
# clean: remove ghost non-master markers, keep tracked and master markers.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

export FILESYNC_HOME="${TMP}/fsys-46-clean"
rm -rf "$FILESYNC_HOME"

anchor="${TMP}/46-clean-anchor"
proj="${anchor}/clean-proj"
mkdir -p "$proj"

fixture="${TMP}/46-clean-repos.json"
jq -n '[{name:"origin",path:"clean-proj",url:null,branch:"main",id:"rid1",merge_using_git:false}]' >"$fixture"
filesync_test_seed_global_repos "$anchor" "$fixture" || die "seed global repos"

(
	cd "$proj"
	filesync init --no-repo

	printf '%s\n' '# filesync kind=clone path=tools/demo.txt repo=origin repo_id=rid1' 'ghost clone body' >ghost-clone.txt
	printf '%s\n' '# filesync kind=detached path=tools/demo.txt repo=origin repo_id=rid1' 'ghost detached body' >ghost-detached.txt
	printf '%s\n' '# filesync kind=clone path=tools/demo.txt repo=origin repo_id=rid1' 'tracked body' >tracked-clone.txt
	printf '%s\n' '# filesync kind=master' 'master body' >untracked-master.txt

	jq -n \
		'[{
      repo_id:"rid1",
      repo_file_path:"tools/demo.txt",
      local_path:"tracked-clone.txt",
      sync_status:"synced"
    }]' >".filesync/files.json"

	out="$(filesync doctor clean 2>&1)" || die "doctor clean should exit 0"
	[[ "${out}" == *"ghosts_cleaned=2"* ]] || die "clean summary should report two cleaned ghosts"
	[[ "${out}" == *"tracked_non_master=1"* ]] || die "clean summary should report one tracked non-master"

	! grep -q 'filesync kind=' ghost-clone.txt || die "ghost clone marker should be removed"
	! grep -q 'filesync kind=' ghost-detached.txt || die "ghost detached marker should be removed"
	grep -q 'filesync kind=clone' tracked-clone.txt || die "tracked non-master marker should remain"
	grep -q 'filesync kind=master' untracked-master.txt || die "master marker should remain"
)
