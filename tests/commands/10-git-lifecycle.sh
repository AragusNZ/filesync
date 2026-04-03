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
		echo "# filesync kind=master"
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
		'[{"name":"origin","path":"../git-master","url":$url,"branch":"main"}]' >"${TMP}/seed-10.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-10.json"
	filesync add-file origin tools/demo.txt
	[[ -f tools/demo.txt ]] || die "add-file should create local file"
	grep -q 'filesync kind=clone' tools/demo.txt || die "add-file should set clone marker on local"
	_ll="$(filesync list-files --file=demo.txt 2>&1)" || die "list-files --file exit"
	[[ "${_ll}" == *tools/demo.txt* ]] || die "list-files --file should show matching row"
	_dr="$(filesync sync --dry-run --showall 2>&1)" || die "sync --dry-run exit"
	[[ "${_dr}" == *"Already in sync"* ]] || die "dry-run --showall should report already in sync after add-file"
	filesync sync
	[[ -f tools/demo.txt ]] || die "sync should keep local file"
	grep -q 'filesync kind=clone' tools/demo.txt || die "local should be clone"
	filesync check >/dev/null || die "check after sync"
	echo "local-edit" >>tools/demo.txt
	filesync check >/dev/null || die "check after local edit"
	filesync push tools/demo.txt
	grep -q 'local-edit' "${master}/tools/demo.txt" || die "push should update master"
	filesync detach-file tools/demo.txt
	jq -e '.[] | select(.local_path=="tools/demo.txt") | .sync_status == "detached"' ".filesync/files.json" >/dev/null || die "detach status"
	grep -q 'filesync kind=detached' tools/demo.txt || die "detach marker"
	filesync attach-file tools/demo.txt
	jq -e '.[] | select(.local_path=="tools/demo.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null || die "attach + check should leave synced"
	grep -q 'filesync kind=clone' tools/demo.txt || die "attach clone marker"
	filesync check >/dev/null || die "check after attach"
	mkdir -p "${master}/public"
	{
		echo '<!DOCTYPE html><html>'
		echo '<!-- filesync kind=master -->'
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
	grep -qF '<!-- filesync kind=clone' public/page.html || die "html clone marker"
	filesync check --file=page.html >/dev/null || die "check html"
	filesync rmf public/page.html
	grep -qF 'kind=master' "${master}/public/page.html" || die "rm must leave master repo marker"
	! grep -q 'filesync kind=clone' public/page.html || die "rm should strip local clone marker"
	{
		echo "extra-body"
		echo "# filesync kind=master"
	} >"${master}/tools/extra.txt"
	(
		cd "${master}"
		git add tools/extra.txt
		git commit -q -m extra
	)
	filesync add-file origin tools/extra.txt
	filesync sync
	[[ -f tools/extra.txt ]] || die "sync extra"
	filesync rmf tools/extra.txt
	[[ "$(jq '. | length' .filesync/files.json)" -eq 1 ]] || die "rm should leave one row"
	filesync edit-repo origin --rename=upstream
	jq -e '.[] | select(.local_path=="tools/demo.txt") | .repo_name == "origin"' ".filesync/files.json" >/dev/null || die "edit-repo rename leaves project files.json repo_name"
	grep -qF 'repo=origin' tools/demo.txt || die "edit-repo does not rewrite clone marker"
	_ru="$(filesync list-repos --repo=upstream 2>&1)" || die "list-repos upstream"
	[[ "${_ru}" == *upstream* ]] || die "list-repos filter upstream"
	_sda="$(filesync sync --dry-run --status=all 2>&1)" || die "sync --status=all dry-run exit"
	[[ "${_sda,,}" == *sync* ]] || [[ "${_sda}" == *"Nothing"* ]] || [[ "${_sda,,}" == *already* ]] || die "sync --status=all dry-run"
)
