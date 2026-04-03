#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

# edit-repo uses system init: renames global repos.json only; no project scans or files.json/marker updates.
master="${TMP}/er-guard-master"
proj_a="${TMP}/er-guard-a"
proj_b="${TMP}/er-guard-b"
rm -rf "${master}" "${proj_a}" "${proj_b}"

mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	filesync init
	mkdir -p tools
	{
		echo "MASTER_X"
		echo "# filesync kind=master"
	} >tools/x.txt
	git add tools/x.txt
	git commit -q -m init
)

mkdir -p "${proj_b}"
(
	cd "${proj_b}"
	filesync init
)

mkdir -p "${proj_a}"
(
	cd "${proj_a}"
	filesync init
	jq -n \
		--arg master "${master}" \
		--arg b "${proj_b}" \
		'[
			{"name":"emissions","path":$master,"url":null,"branch":"main"},
			{"name":"greenlit-api","path":$b,"url":null,"branch":null}
		]' >"${TMP}/seed-30.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-30.json"
	filesync add-collection sib --repos=greenlit-api
	filesync add-file emissions tools/x.txt --also=sib
)

(
	cd "${proj_a}"
	filesync disable emissions
	filesync config repo greenlit-api mirror-in false
	filesync edit-repo emissions --rename=em2
	jq -e 'any(.name == "em2")' "${FILESYNC_HOME}/repos.json" >/dev/null || die "global repos should list em2"
	jq -e '.[] | select(.local_path=="tools/x.txt") | .repo_name == "emissions"' ".filesync/files.json" >/dev/null || die "project files.json keeps old repo_name"
	grep -qF 'repo=emissions' "tools/x.txt" || die "marker unchanged"
)

(
	cd "${proj_b}"
	jq -e '.[] | select(.local_path=="tools/x.txt") | .repo_name == "emissions"' ".filesync/files.json" >/dev/null || die "proj_b files.json unchanged"
	grep -qF 'repo=emissions' "tools/x.txt" || die "proj_b marker unchanged"
)

(
	cd "${proj_a}"
	filesync remove-repo em2 2>/dev/null && die "remove-repo should require --force when mappings exist"
	filesync remove-repo em2 --force -y
)
