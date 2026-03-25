#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/git-master" proj="${TMP}/git-proj"
rm -rf "${master}" "${proj}"
mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	mkdir -p tools
	{
		echo "content-v1"
		echo "# filesync:sync kind=master"
	} >tools/demo.txt
	git add tools/demo.txt
	git commit -q -m init
)
mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init
	jq -n \
		--arg url "file://${master}" \
		'[{"name":"origin","path":"../git-master","url":$url,"branch":"main"}]' >".filesync/repos.json"
	filesync add-file origin tools/demo.txt
	_ll="$(filesync list-files --file=demo.txt 2>&1)" || die "list-files --file exit"
	[[ "${_ll}" == *tools/demo.txt* ]] || die "list-files --file should show matching row"
	_dr="$(filesync sync --dry-run 2>&1)" || die "sync --dry-run exit"
	[[ "${_dr}" == *"Would sync"* ]] || die "dry-run should mention Would sync"
	[[ ! -f tools/demo.txt ]] || die "dry-run must not create local file"
	filesync sync
	[[ -f tools/demo.txt ]] || die "sync should create local file"
	grep -q 'filesync:sync kind=clone' tools/demo.txt || die "local should be clone"
	filesync check >/dev/null || die "check after sync"
	echo "local-edit" >>tools/demo.txt
	filesync check >/dev/null || die "check after local edit"
	filesync push tools/demo.txt
	grep -q 'local-edit' "${master}/tools/demo.txt" || die "push should update master"
	filesync detach tools/demo.txt
	jq -e '.[] | select(.local_path=="tools/demo.txt") | .sync_status == "detached"' ".filesync/files.json" >/dev/null || die "detach status"
	grep -q 'filesync:sync kind=detached' tools/demo.txt || die "detach marker"
	filesync attach tools/demo.txt
	jq -e '.[] | select(.local_path=="tools/demo.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null || die "attach + check should leave synced"
	grep -q 'filesync:sync kind=clone' tools/demo.txt || die "attach clone marker"
	filesync check >/dev/null || die "check after attach"
	mkdir -p "${master}/public"
	{
		echo '<!DOCTYPE html><html>'
		echo '<!-- filesync:sync kind=master -->'
		echo '</html>'
	} >"${master}/public/page.html"
	(
		cd "${master}"
		git add public/page.html
		git commit -q -m page
	)
	filesync add-file origin public/page.html
	filesync sync
	[[ -f public/page.html ]] || die "sync html"
	grep -qF '<!-- filesync:sync kind=clone' public/page.html || die "html clone marker"
	filesync check --file=page.html >/dev/null || die "check html"
	filesync rm public/page.html
	{
		echo "extra-body"
		echo "# filesync:sync kind=master"
	} >"${master}/tools/extra.txt"
	(
		cd "${master}"
		git add tools/extra.txt
		git commit -q -m extra
	)
	filesync add-file origin tools/extra.txt
	filesync sync
	[[ -f tools/extra.txt ]] || die "sync extra"
	filesync rm tools/extra.txt
	[[ "$(jq '. | length' .filesync/files.json)" -eq 1 ]] || die "rm should leave one row"
	filesync edit-repo origin --rename=upstream
	jq -e '.[] | select(.local_path=="tools/demo.txt") | .repo_name == "upstream"' ".filesync/files.json" >/dev/null || die "edit-repo rename files.json"
	_ru="$(filesync list-repos --repo=upstream 2>&1)" || die "list-repos upstream"
	[[ "${_ru}" == *upstream* ]] || die "list-repos filter upstream"
	_sda="$(filesync sync --dry-run --all 2>&1)" || die "sync --all dry-run exit"
	[[ "${_sda,,}" == *sync* ]] || [[ "${_sda}" == *"Nothing"* ]] || [[ "${_sda,,}" == *already* ]] || die "sync --all dry-run"
)
