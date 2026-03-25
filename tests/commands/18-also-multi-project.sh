#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/also-master"
proj_a="${TMP}/also-proj-a"
proj_b="${TMP}/also-proj-b"
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
	jq -n \
		--arg p "${master}" \
		'[{"name":"emissions","path":$p,"url":null,"branch":"main"}]' >".filesync/repos.json"
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
		]' >".filesync/repos.json"

	filesync add-file emissions tools/x.txt --also=greenlit-api

	[[ -f "tools/x.txt" ]] || die "proj_a should have local clone"
	grep -qE 'filesync kind=clone' "tools/x.txt" || die "proj_a local should be clone"
)

(
	cd "${proj_b}"
	[[ -f "tools/x.txt" ]] || die "proj_b should have local clone from --also"
	grep -qE 'filesync kind=clone' "tools/x.txt" || die "proj_b local should be clone"
	jq -e '.[] | select(.local_path=="tools/x.txt")' ".filesync/files.json" >/dev/null || die "proj_b should have files.json row from --also"
)

# add-master: only mirror mapping rows to sibling projects (sync_required)
(
	cd "${proj_a}"
	mkdir -p tools
	{
		echo "PROMOTE_ME"
		echo "# filesync kind=clone path=tools/promoted.txt repo=emissions"
	} >"tools/promoted.txt"
	filesync add-master emissions tools/promoted.txt --also=greenlit-api
)

grep -qE 'filesync kind=master' "${master}/tools/promoted.txt" || die "master repo should contain promoted master marker"

(
	cd "${proj_b}"
	jq -e '.[] | select(.local_path=="tools/promoted.txt") | .sync_status == "sync_required"' ".filesync/files.json" >/dev/null \
		|| die "proj_b mirrored add-master row should start as sync_required"
)

