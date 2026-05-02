#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/erid-master"
proj_a="${TMP}/erid-a"
proj_b="${TMP}/erid-b"
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
		]' >"${TMP}/seed-48.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-48.json"
	filesync new collection sib --repos=greenlit-api
	filesync add emissions tools/x.txt --also=sib
)

(
	cd "${proj_a}"
	if filesync edit repo emissions --id=testid-greenlit-api 2>/dev/null; then
		die "edit-repo --id should reject duplicate of another repo id"
	fi
	filesync edit repo emissions --id=custom-em-99
	jq -e '.[] | select(.name=="emissions") | .id == "custom-em-99"' "${FILESYNC_HOME}/repos.json" >/dev/null \
		|| die "global repos.json id updated"
	jq -e '.[] | select(.local_path=="tools/x.txt") | .repo_id == "custom-em-99"' ".filesync/files.json" >/dev/null \
		|| die "proj_a files.json repo_id"
	grep -qF 'repo_id=custom-em-99' "tools/x.txt" || die "proj_a clone marker repo_id"
)

(
	cd "${proj_b}"
	jq -e '.[] | select(.local_path=="tools/x.txt") | .repo_id == "custom-em-99"' ".filesync/files.json" >/dev/null \
		|| die "proj_b files.json repo_id"
	grep -qF 'repo_id=custom-em-99' "tools/x.txt" || die "proj_b clone marker repo_id"
)
