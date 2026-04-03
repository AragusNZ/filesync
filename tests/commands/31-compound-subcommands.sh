#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

_empty="$(mktemp -d "${TMP}/fs-compound.XXXXXX")"
cd "$_empty"

_out="$(filesync list repos --help 2>&1)" || die "list repos --help"
[[ "${_out}" == *"list repos"* ]] || die "list repos help missing phrase"

_out="$(filesync l -r --help 2>&1)" || die "l -r --help"
[[ "${_out}" == *"list repos"* ]] || die "l -r help"

_out="$(filesync list files --help 2>&1)" || die "list files --help"
[[ "${_out}" == *"list files"* ]] || die "list files help"

_out="$(filesync l --help 2>&1)" || die "l --help"
[[ "${_out}" == *"list files"* ]] || die "bare l help should be list files"

_out="$(filesync add file --help 2>&1)" || die "add file --help"
[[ "${_out}" == *"add file"* || "${_out}" == *"path_in_repo"* ]] || die "add file help"

_out="$(filesync a --help 2>&1)" || die "a --help"
[[ "${_out}" == *"add file"* || "${_out}" == *"path_in_repo"* ]] || die "a help"

_out="$(filesync edit repo --help 2>&1)" || die "edit repo --help"
[[ "${_out}" == *"--disable"* ]] || die "edit repo help should mention --disable"

_out="$(filesync e -r --help 2>&1)" || die "e -r --help"
[[ "${_out}" == *"--disable"* ]] || die "e -r help"

if filesync enable x 2>/dev/null; then
	die "enable should be removed"
fi
if filesync progress 2>/dev/null; then
	die "progress should be removed"
fi
