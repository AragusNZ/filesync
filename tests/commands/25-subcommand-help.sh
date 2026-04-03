#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

_empty="$(mktemp -d "${TMP}/fs-subcmd-help.XXXXXX")"
cd "$_empty"

assert_help() {
	local _msg="$1" _needle="$2"
	shift 2
	local _out
	_out="$(filesync "$@" 2>&1)" || die "${_msg}: nonzero exit"
	[[ "${_out}" == *"${_needle}"* ]] || die "${_msg}: output missing ${_needle}"
}

assert_help "sync --help" "--dry-run" sync --help
assert_help "sync --help" "-c, --check" sync --help
assert_help "sync alias s -h" "master repos" s -h
assert_help "check --help" "last_check_at" check --help
assert_help "check alias c -h" "Verify mappings" c -h
assert_help "init --help" ".filesync/" init --help
assert_help "init --help" "--no-repo" init --help
assert_help "list-repos --help" "list-repos" list-repos --help
assert_help "list-files -h" "list-files" list-files -h
assert_help "enable --help" "check_sync_enabled" enable --help
assert_help "disable -h" "check_sync_enabled" disable -h
assert_help "update --help" "GitHub" update --help
assert_help "config --help" "doctor" config --help
assert_help "progress --help" "percent" progress --help
assert_help "add-file --help" "add-file" add-file --help
assert_help "add-master -h" "add-master" add-master -h
assert_help "add-clone --help" "add-clone" add-clone --help
assert_help "push --help" "--all" push --help
assert_help "detach-file --help" "detached" detach-file --help
assert_help "attach-file --help" "Re-couple" attach-file --help
assert_help "detach-repo --help" "detach-repo" detach-repo --help
assert_help "attach-repo -h" "attach-repo" attach-repo -h
assert_help "remove-file --help" "files.json" remove-file --help
assert_help "remove-file --help" "--all-missing" remove-file --help
assert_help "rmf --help" "--all-missing" rmf --help
assert_help "remove-repo --help" "repos.json" remove-repo --help
assert_help "add-repo --help" "Interactively" add-repo --help
assert_help "edit-repo --help" "--rename" edit-repo --help
assert_help "add-collection --help" "collections.json" add-collection --help
assert_help "remove-collection --help" "collections.json" remove-collection --help
assert_help "list-collections -h" "list-collections" list-collections -h
assert_help "list-collections alias lcol -h" "list-collections" lcol -h
assert_help "edit-collection --help" "--add-repo" edit-collection --help
assert_help "config --help" "system-home" config --help
assert_help "migrate --help" "legacy-backup" migrate --help
assert_help "handle-missing --help" "--recreate-from-master" handle-missing --help
