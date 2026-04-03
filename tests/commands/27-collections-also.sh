#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/coll-also-master"
proj_a="${TMP}/coll-also-a"
proj_b="${TMP}/coll-also-b"
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
		]' >"${TMP}/seed-27a.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-27a.json"

	filesync add-collection siblings --repos=greenlit-api

	filesync add-file emissions tools/x.txt --also=siblings

	[[ -f "tools/x.txt" ]] || die "proj_a should have local clone"
	grep -qE 'filesync kind=clone' "tools/x.txt" || die "proj_a local should be clone"
)

(
	cd "${proj_b}"
	[[ -f "tools/x.txt" ]] || die "proj_b should have local clone from collection --also"
	jq -e '.[] | select(.local_path=="tools/x.txt")' ".filesync/files.json" >/dev/null || die "proj_b files.json row"
)

# add-collection name must not match repo name
(
	cd "${proj_a}"
	if filesync add-collection emissions 2>/dev/null; then
		die "add-collection should reject repo-named emissions"
	fi
)

# add-repo name must not match collection name
(
	cd "${proj_a}"
	filesync add-collection dupname --repos=greenlit-api
	if printf '%s\n' 'dupname' 'u' '../x' 'main' | filesync add-repo 2>/dev/null; then
		die "add-repo should reject name dupname (collection exists)"
	fi
	filesync remove-collection dupname
)

# edit-repo --rename must not target collection name
(
	cd "${proj_a}"
	filesync add-collection holdname --repos=greenlit-api
	if filesync edit-repo emissions --rename=holdname 2>/dev/null; then
		die "edit-repo should reject rename to collection holdname"
	fi
	filesync remove-collection holdname
)

# remove-repo strips collection membership and drops empty collection
(
	cd "${proj_a}"
	jq -n \
		--arg x "${TMP}/coll-also-x" \
		'[{"name":"solo","path":$x,"url":null,"branch":"main"}]' >"${TMP}/seed-27b.json"
	filesync_test_append_global_repos "${TMP}/seed-27b.json"
	mkdir -p "${TMP}/coll-also-x"
	(
		cd "${TMP}/coll-also-x"
		filesync init
	)
	filesync add-collection tworepo --repos=greenlit-api,solo
	jq -e '.[] | select(.name=="tworepo") | .repos | length == 2' "${FILESYNC_HOME}/collections.json" >/dev/null || die "tworepo should list 2 repos"
	filesync remove-repo -y solo
	jq -e '.[] | select(.name=="tworepo") | .repos == ["greenlit-api"]' "${FILESYNC_HOME}/collections.json" >/dev/null || die "tworepo should only list greenlit-api after solo removed"
	filesync remove-repo -y greenlit-api
	! jq -e '.[] | select(.name=="tworepo")' "${FILESYNC_HOME}/collections.json" >/dev/null || die "empty tworepo collection should be removed"
)
