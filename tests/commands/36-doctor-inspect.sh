#!/usr/bin/env bash
# doctor inspect: warns when global repos.json paths do not exist on disk.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

export FILESYNC_HOME="${TMP}/fsys-36-doctor"
rm -rf "$FILESYNC_HOME"

anchor="${TMP}/36-doctor-anchor"
mkdir -p "${anchor}/real-repo"
fixture="${TMP}/36-doctor-repos.json"
jq -n \
	'[
    {name:"good",path:"real-repo",url:null,branch:"main",id:"id-good",merge_using_git:false},
    {name:"bad",path:"missing-dir",url:null,branch:"main",id:"id-bad",merge_using_git:false}
  ]' >"$fixture"

filesync_test_seed_global_repos "$anchor" "$fixture" || die "seed global repos"

out="$(filesync doctor 2>&1)" || die "doctor"
echo "$out" | grep -qF 'Warning: repo checkout path missing or not a directory:' || die "doctor should warn about paths"
echo "$out" | grep -qF "repo 'bad':" || die "doctor should name the bad repo"
echo "$out" | grep -qF 'missing-dir' || die "doctor should mention the configured path"

jq -n \
	'[{name:"solo",path:"real-repo",url:null,branch:"main",id:"id-solo",merge_using_git:false}]' >"$fixture"
filesync_test_seed_global_repos "$anchor" "$fixture" || die "seed ok repos"

out_ok="$(filesync doctor inspect 2>&1)" || die "doctor inspect ok"
echo "$out_ok" | grep -qF 'Global repos.json: all checkout directories exist.' || die "doctor should report all paths ok"
echo "$out_ok" | grep -qF 'Summary:' || die "doctor should print summary"
