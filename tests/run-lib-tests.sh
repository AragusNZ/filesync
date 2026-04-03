#!/usr/bin/env bash
# Library module tests (no staged install). Usage: run-lib-tests.sh [options] REPO_ROOT
# Options: --filter SUBSTR (repeatable; basename must contain SUBSTR); any filter matches (OR).
#          --list        print selected test files and exit 0
#          --quiet, -q   suppress output for passing tests; print only failures
# Env:     FILESYNC_TEST_QUIET=1  same as --quiet
set -euo pipefail

ROOT=""
filters=()
list_only=0
quiet="${FILESYNC_TEST_QUIET:-0}"
[[ "${quiet}" == "1" ]] || quiet=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--filter)
			[[ $# -ge 2 ]] || { echo "run-lib-tests: --filter needs a value" >&2; exit 2; }
			filters+=("$2")
			shift 2
			;;
		--list)
			list_only=1
			shift
			;;
		--quiet|-q)
			quiet=1
			shift
			;;
		--)
			shift
			break
			;;
		-*)
			echo "run-lib-tests: unknown option $1" >&2
			exit 2
			;;
		*)
			ROOT="$1"
			shift
			break
			;;
	esac
done

if [[ -z "${ROOT}" ]] && [[ $# -ge 1 ]]; then
	ROOT="$1"
	shift
fi
ROOT="${ROOT:?repo root required}"

TESTS="$(cd "$(dirname "${0}")" && pwd)"
shopt -s nullglob
mapfile -t all_files < <(printf '%s\n' "${TESTS}/lib/"*.sh | LC_ALL=C sort)

matches_filters() {
	local base="$1"
	if [[ ${#filters[@]} -eq 0 ]]; then
		return 0
	fi
	local f
	for f in "${filters[@]}"; do
		if [[ "${base}" == *"${f}"* ]]; then
			return 0
		fi
	done
	return 1
}

selected=()
for f in "${all_files[@]}"; do
	base="$(basename "${f}")"
	if ! matches_filters "${base}"; then
		continue
	fi
	selected+=("${f}")
done

if [[ "${list_only}" -eq 1 ]]; then
	printf '%s\n' "${selected[@]}"
	exit 0
fi

if [[ ${#selected[@]} -eq 0 ]]; then
	echo "run-lib-tests: no test files selected" >&2
	exit 1
fi

LIB_TEST_TMP="$(mktemp -d)"
cleanup() { rm -rf "${LIB_TEST_TMP}"; }
trap cleanup EXIT
export LIB_TEST_TMP ROOT

failed=()
passed=()
for f in "${selected[@]}"; do
	base="$(basename "${f}")"
	if [[ "${quiet}" -eq 1 ]]; then
		_tlog="$(mktemp)"
		if env FILESYNC_HOME="${LIB_TEST_TMP}/sys-${base%.sh}" bash "${f}" "${ROOT}" >"${_tlog}" 2>&1 </dev/null; then
			rm -f "${_tlog}"
			passed+=("${base}")
		else
			echo "  --- ${base} ---" >&2
			cat "${_tlog}" >&2
			rm -f "${_tlog}"
			failed+=("${base}")
		fi
	else
		echo "  --- ${base} ---"
		if env FILESYNC_HOME="${LIB_TEST_TMP}/sys-${base%.sh}" bash "${f}" "${ROOT}" </dev/null; then
			passed+=("${base}")
		else
			failed+=("${base}")
		fi
	fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
	echo "run-lib-tests: FAILED: ${failed[*]}" >&2
	echo "run-lib-tests: passed: ${passed[*]}" >&2
	exit 1
fi
if [[ "${quiet}" -eq 0 ]]; then
	echo "run-lib-tests: all passed (${#passed[@]} files)."
fi
