#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

base="${TMP}/col-cli"
r1="${base}/repo-one"
r2="${base}/repo-two"
rm -rf "${base}"
mkdir -p "${r1}" "${r2}"
(
	cd "${r1}"
	filesync init
)
(
	cd "${r2}"
	filesync init
)

proj="${base}/consumer"
mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init
	jq -n \
		--arg a "${r1}" \
		--arg b "${r2}" \
		'[
			{"name":"one","path":$a,"url":null,"branch":null},
			{"name":"two","path":$b,"url":null,"branch":null}
		]' >".filesync/repos.json"

	filesync add-collection grp
	filesync edit-collection grp --add-repo=one || die "edit-collection --add-repo"
	filesync edit-collection grp --add-repo=two || die "edit-collection second add"
	jq -e '.[] | select(.name=="grp") | .repos == ["one","two"]' ".filesync/collections.json" >/dev/null || die "grp repos"

	if filesync edit-collection grp --add-repo=one 2>/dev/null; then
		die "edit-collection should reject duplicate repo in collection"
	fi

	filesync edit-collection grp --remove-repo=one || die "edit-collection --remove-repo"
	jq -e '.[] | select(.name=="grp") | .repos == ["two"]' ".filesync/collections.json" >/dev/null || die "grp after remove"

	filesync edit-collection grp --rename=renamed || die "edit-collection --rename"
	! jq -e '.[] | select(.name=="grp")' ".filesync/collections.json" >/dev/null || die "old name should be gone"
	jq -e '.[] | select(.name=="renamed") | .repos == ["two"]' ".filesync/collections.json" >/dev/null || die "renamed repos"

	_out="$(filesync list-collections 2>&1)" || die "list-collections"
	[[ "${_out}" == *renamed* ]] || die "list-collections should mention collection"
	[[ "${_out}" == *two* ]] || die "list-collections should mention repo"

	filesync remove-collection renamed || die "remove-collection"
	[[ "$(jq 'length' ".filesync/collections.json")" -eq 0 ]] || die "collections should be empty"

	_out="$(filesync list-collections 2>&1)" || die "list-collections empty"
	[[ "${_out}" == *"no collections defined"* ]] || die "list-collections empty message"

	filesync add-collection solo
	if filesync add-collection solo 2>/dev/null; then
		die "add-collection should reject duplicate collection name"
	fi
	filesync remove-collection solo

	_out="$(filesync lcol 2>&1)" || die "lcol"
	[[ "${_out}" == *"no collections defined"* ]] || die "lcol empty collections message"
)

# --also errors need a master file + emissions-style repo
master="${base}/m"
mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	filesync init
	mkdir -p tools
	{
		echo "M"
		echo "# filesync kind=master"
	} >tools/x.txt
	git add tools/x.txt
	git commit -q -m init
)

cproj="${base}/cproj"
mkdir -p "${cproj}"
(
	cd "${cproj}"
	filesync init
	jq -n --arg p "${master}" '[{"name":"emissions","path":$p,"url":null,"branch":"main"}]' >".filesync/repos.json"

	if filesync add-file emissions tools/x.txt --also=not_a_collection_or_repo 2>/dev/null; then
		die "add-file should fail on unknown --also token"
	fi

	filesync add-collection ecoll
	if filesync add-file emissions tools/x.txt --also=ecoll 2>/dev/null; then
		die "add-file should fail --also on empty collection"
	fi
)
