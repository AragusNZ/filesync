#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/sync-missing-local-master"
proj="${TMP}/sync-missing-local-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}" "${proj}"

(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p database/seeders
	{
		echo "v1"
		echo "# filesync kind=master"
	} >database/seeders/LoadsDataFilesTrait.php
	git add database/seeders/LoadsDataFilesTrait.php
	git commit -q -m init
)

(
	cd "${proj}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../sync-missing-local-master","url":$url,"branch":"main"}]' >".filesync/repos.json"

	filesync add-file origin database/seeders/LoadsDataFilesTrait.php
	filesync sync

	rm -f database/seeders/LoadsDataFilesTrait.php

	# check should fail and mark the row as error_missing_local
	filesync check >/dev/null && die "check should fail when local file is missing"
	jq -e '.[] | select(.local_path=="database/seeders/LoadsDataFilesTrait.php") | .sync_status == "error_missing_local"' ".filesync/files.json" >/dev/null \
		|| die "expected error_missing_local status after check"

	# sync should recreate the missing file by default (no --status= needed)
	filesync sync
	[[ -f database/seeders/LoadsDataFilesTrait.php ]] || die "sync should recreate missing local file"
	grep -q '^v1$' database/seeders/LoadsDataFilesTrait.php || die "recreated file should match master content"
)

