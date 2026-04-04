#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

# list files: --repo-file and --all-files match repo_file_path; --file is local only; AND across dimensions.
master="${TMP}/pf-dim-master" proj="${TMP}/pf-dim-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}" "${proj}"
(
	cd "${proj}"
	filesync init
	jq -n \
		--arg p "${master}" \
		'[{"name":"origin","path":$p,"url":"","branch":"main"}]' >"${TMP}/seed-40.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-40.json"
	jq -n \
		'[
			{"repo_id":"testid-origin","repo_file_path":"vendor/pkg/x.txt","local_path":"copy/x.txt","sync_status":"synced","last_check_at":null},
			{"repo_id":"testid-origin","repo_file_path":"tools/y.txt","local_path":"tools/y.txt","sync_status":"synced","last_check_at":null}
		]' >".filesync/files.json"

	_rfp=$(filesync list files --repo-file=vendor/pkg 2>&1) || die "list --repo-file"
	echo "$_rfp" | grep -qF 'vendor/pkg/x.txt' || die "repo-file should list vendor row"
	echo "$_rfp" | grep -qF 'copy/x.txt' || die "repo-file row should show local path"
	[[ $(echo "$_rfp" | grep -cF 'tools/y.txt') -eq 0 ]] || die "repo-file should exclude tools/y row"

	_af=$(filesync list files --all-files=vendor/pkg 2>&1) || die "list --all-files"
	echo "$_af" | grep -qF 'copy/x.txt' || die "all-files should match repo path"
	[[ $(echo "$_af" | grep -cF 'tools/y.txt') -eq 0 ]] || die "all-files vendor should exclude y row"

	_fl=$(filesync list files --file=copy 2>&1) || die "list --file local"
	echo "$_fl" | grep -qF 'copy/x.txt' || die "file=copy should hit copy/x local"
	[[ $(echo "$_fl" | grep -cF 'tools/y.txt') -eq 0 ]] || die "file=copy should exclude tools/y"

	_and=$(filesync list files --file=copy --repo-file=x.txt 2>&1) || die "list AND"
	echo "$_and" | grep -qF 'copy/x.txt' || die "AND should keep vendor row"
	[[ $(echo "$_and" | grep -cF 'tools/y.txt') -eq 0 ]] || die "AND should exclude second row"

	_onlyy=$(filesync list files --file=tools/y 2>&1) || die "list second row"
	echo "$_onlyy" | grep -qF 'tools/y.txt' || die "file=tools/y should list second row"
	[[ $(echo "$_onlyy" | grep -cF 'vendor/pkg') -eq 0 ]] || die "file=tools/y should exclude vendor row"
)
