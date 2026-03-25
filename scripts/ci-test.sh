#!/usr/bin/env bash
# Full project test suite: staged install smoke, CLI matrix, git-backed integration.
# Usage: from repo root — bash scripts/ci-test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

EXPECTED_VERSION="$(tr -d '\r\n' <"${ROOT}/share/VERSION")"

die() {
	echo "FAIL: $*" >&2
	exit 1
}

stage_install() {
	local dest="$1" prefix="$2"
	make -C "${ROOT}" install DESTDIR="${dest}" PREFIX="${prefix}"
	export PATH="${dest}${prefix}/bin:${PATH}"
}

case_prefix_smoke() {
	local label="$1" dest="$2" prefix="$3"
	mkdir -p "${dest}"
	stage_install "${dest}" "${prefix}"
	local fs
	fs="$(command -v filesync)"
	readlink -f "${fs}" | grep -q 'lib/filesync' || die "filesync not resolved under lib/filesync (${fs})"
	_m="$(MANPATH="${dest}${prefix}/share/man" man filesync 2>&1)" || die "man filesync"
	[[ "${_m}" == *filesync* ]] || die "man filesync body"
	mkdir -p "${TMP}/proj-${label}"
	(
		cd "${TMP}/proj-${label}"
		filesync init
		[[ -f .filesync/config.json && -f .filesync/repos.json && -f .filesync/files.json ]] || die "init missing json"
		[[ "$(filesync help 2>&1)" == *filesync* ]] || die "help"
		filesync check >/dev/null || die "check empty project"
		[[ "$(filesync --version 2>&1)" == *"filesync ${EXPECTED_VERSION}"* ]] || die "--version"
		[[ "$(filesync -V 2>&1)" == *"filesync ${EXPECTED_VERSION}"* ]] || die "-V"
	)
}

case_dispatch() {
	stage_install "${TMP}/st-dispatch" /usr/local
	mkdir -p "${TMP}/dispatch-proj/dummy-repo"
	(
		cd "${TMP}/dispatch-proj"
		filesync init
		jq -n '[{"name":"d","path":"dummy-repo","url":"u","branch":"main"}]' >".filesync/repos.json"
		if filesync not_a_real_subcommand_zz 2>/dev/null; then
			die "unknown subcommand should fail"
		fi
		_d="$(filesync --dry-run 2>&1)" || die "flag-first sync exit"
		[[ "${_d,,}" == *sync* ]] || die "flag-first should run sync"
	)
}

case_init_edges() {
	stage_install "${TMP}/st-init" /usr/local
	local p="${TMP}/init-edges"
	mkdir -p "${p}"
	(
		cd "${p}"
		filesync init
		if filesync init 2>/dev/null; then
			die "init twice should fail"
		fi
	)
	rm -f "${p}/.filesync/files.json"
	(
		cd "${p}"
		filesync init
		[[ -f "${p}/.filesync/files.json" ]] || die "init should restore missing files.json"
	)
}

case_env_project_root() {
	stage_install "${TMP}/st-env" /usr/local
	local p="${TMP}/env-root"
	mkdir -p "${p}"
	(
		cd "${p}"
		filesync init
	)
	mkdir -p "${TMP}/outside"
	(
		cd "${TMP}/outside"
		FILESYNC_PROJECT_ROOT="${p}" filesync check >/dev/null || die "FILESYNC_PROJECT_ROOT check"
	)
}

case_enable_disable() {
	stage_install "${TMP}/st-ed" /usr/local
	local p="${TMP}/ed-proj"
	mkdir -p "${p}"
	(
		cd "${p}"
		filesync init
		filesync disable
		filesync check >/dev/null || die "check when disabled"
		filesync sync >/dev/null || die "sync when disabled"
		printf '%s\n' y | filesync enable
		filesync check >/dev/null || die "check after enable"
	)
}

case_repos_list() {
	stage_install "${TMP}/st-rl" /usr/local
	local p="${TMP}/rl-proj"
	mkdir -p "${p}"
	(
		cd "${p}"
		filesync init
		filesync repos >/dev/null || die "repos empty"
		filesync list >/dev/null || die "list empty"
		if filesync repos --repo=nosuchrepo 2>/dev/null; then
			die "repos --repo missing should fail"
		fi
	)
}

case_sync_no_repos() {
	stage_install "${TMP}/st-sn" /usr/local
	local p="${TMP}/sn-proj"
	mkdir -p "${p}"
	(
		cd "${p}"
		filesync init
		printf '%s\n' '[]' | jq . >".filesync/repos.json"
		if filesync sync 2>/dev/null; then
			die "sync with zero repos should fail"
		fi
	)
}

case_update_help() {
	stage_install "${TMP}/st-up" /usr/local
	_uh="$(filesync update --help 2>&1)" || die "update --help"
	[[ "${_uh}" == *apply* ]] || die "update --help body"
}

case_git_lifecycle() {
	stage_install "${TMP}/st-git" /usr/local
	local master="${TMP}/git-master" proj="${TMP}/git-proj"
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
			echo "// >> FILE-SYNC: MASTER"
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
		filesync add origin tools/demo.txt
		_dr="$(filesync sync --dry-run 2>&1)" || die "sync --dry-run exit"
		[[ "${_dr}" == *"Would sync"* ]] || die "dry-run should mention Would sync"
		[[ ! -f tools/demo.txt ]] || die "dry-run must not create local file"
		filesync sync
		[[ -f tools/demo.txt ]] || die "sync should create local file"
		grep -q 'FILE-SYNC: CLONE' tools/demo.txt || die "local should be clone"
		filesync check >/dev/null || die "check after sync"
		echo "local-edit" >>tools/demo.txt
		filesync check >/dev/null || die "check after local edit"
		filesync push tools/demo.txt
		grep -q 'local-edit' "${master}/tools/demo.txt" || die "push should update master"
		filesync detach tools/demo.txt
		jq -e '.[] | select(.local_path=="tools/demo.txt") | .sync_status == "uncoupled"' ".filesync/files.json" >/dev/null || die "detach status"
		grep -q 'UNCOUPLED' tools/demo.txt || die "detach marker"
		filesync attach tools/demo.txt
		jq -e '.[] | select(.local_path=="tools/demo.txt") | .sync_status == "synced"' ".filesync/files.json" >/dev/null || die "attach + check should leave synced"
		grep -q 'FILE-SYNC: CLONE' tools/demo.txt || die "attach clone marker"
		filesync check >/dev/null || die "check after attach"
		{
			echo "extra-body"
			echo "// >> FILE-SYNC: MASTER"
		} >"${master}/tools/extra.txt"
		(
			cd "${master}"
			git add tools/extra.txt
			git commit -q -m extra
		)
		filesync add origin tools/extra.txt
		filesync sync
		[[ -f tools/extra.txt ]] || die "sync extra"
		filesync rm tools/extra.txt
		[[ "$(jq '. | length' .filesync/files.json)" -eq 1 ]] || die "rm should leave one row"
		filesync repo-edit origin --rename=upstream
		jq -e '.[] | select(.local_path=="tools/demo.txt") | .repo_name == "upstream"' ".filesync/files.json" >/dev/null || die "repo-edit rename files.json"
		_ru="$(filesync repos --repo=upstream 2>&1)" || die "repos upstream"
		[[ "${_ru}" == *upstream* ]] || die "repos filter upstream"
		_sda="$(filesync sync --dry-run --all 2>&1)" || die "sync --all dry-run exit"
		[[ "${_sda,,}" == *sync* ]] || [[ "${_sda}" == *"Nothing"* ]] || [[ "${_sda,,}" == *already* ]] || die "sync --all dry-run"
	)
}

case_repo_edit_path() {
	stage_install "${TMP}/st-re" /usr/local
	local p="${TMP}/re-proj"
	mkdir -p "${p}"
	(
		cd "${p}"
		filesync init
		jq -n '[{"name":"r1","path":"../x","url":"u","branch":"main"}]' >".filesync/repos.json"
		filesync repo-edit r1 --path=../y
		jq -e '.[] | select(.name=="r1") | .path == "../y"' ".filesync/repos.json" >/dev/null || die "repo-edit --path"
	)
}

main() {
	case_prefix_smoke local "${TMP}/stage-local" /usr/local
	case_prefix_smoke usr "${TMP}/stage-usr" /usr
	export PATH="${TMP}/stage-local/usr/local/bin:${PATH}"
	case_dispatch
	case_init_edges
	case_env_project_root
	case_enable_disable
	case_repos_list
	case_sync_no_repos
	case_update_help
	case_repo_edit_path
	case_git_lifecycle
	bash "${ROOT}/tests/run-lib-tests.sh" "${ROOT}"
	echo "All ci-test.sh cases passed."
}

main "$@"
