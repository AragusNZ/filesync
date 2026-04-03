#!/usr/bin/env bash
# CLI tests against staged install. Usage: run-command-tests.sh [options] REPO_ROOT
# Options: --filter SUBSTR (repeatable; script basename must contain SUBSTR); OR across filters.
#          --list        print selected test files and exit 0
#          --quiet, -q   suppress output for passing tests and staging make; print only failures
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
			[[ $# -ge 2 ]] || { echo "run-command-tests: --filter needs a value" >&2; exit 2; }
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
		-*)
			echo "run-command-tests: unknown option $1" >&2
			exit 2
			;;
		*)
			ROOT="$1"
			shift
			break
			;;
	esac
done

ROOT="${ROOT:?repo root required}"

TESTS="$(cd "$(dirname "${0}")" && pwd)"
EXPECTED_VERSION="$(tr -d '\r\n' <"${ROOT}/share/VERSION")"

shopt -s nullglob
mapfile -t all_files < <(printf '%s\n' "${TESTS}/commands/"*.sh | LC_ALL=C sort)

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
	echo "run-command-tests: no test files selected" >&2
	exit 1
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

export ROOT TMP EXPECTED_VERSION

ensure_staged() {
	if [[ -f "${TMP}/.filesync_test_bindir" ]]; then
		return 0
	fi
	mkdir -p "${TMP}/stage-local"
	if [[ "${quiet}" -eq 1 ]]; then
		local _mklog
		_mklog="$(mktemp)"
		if ! make -C "${ROOT}" install DESTDIR="${TMP}/stage-local" PREFIX=/usr/local >"${_mklog}" 2>&1; then
			cat "${_mklog}" >&2
			rm -f "${_mklog}"
			return 1
		fi
		rm -f "${_mklog}"
	else
		make -C "${ROOT}" install DESTDIR="${TMP}/stage-local" PREFIX=/usr/local
	fi
	printf '%s\n' "${TMP}/stage-local/usr/local/bin" >"${TMP}/.filesync_test_bindir"
}

wants_install_layout=0
for f in "${selected[@]}"; do
	if [[ "$(basename "${f}")" == 01-install-layout.sh ]]; then
		wants_install_layout=1
		break
	fi
done

if [[ "${wants_install_layout}" -eq 1 ]]; then
	if [[ "${quiet}" -eq 1 ]]; then
		_o1log="$(mktemp)"
		if ! bash "${TESTS}/commands/01-install-layout.sh" >"${_o1log}" 2>&1 </dev/null; then
			cat "${_o1log}" >&2
			rm -f "${_o1log}"
			exit 1
		fi
		rm -f "${_o1log}"
	else
		bash "${TESTS}/commands/01-install-layout.sh" </dev/null
	fi
else
	ensure_staged
fi

_bindir="$(tr -d '\r\n' <"${TMP}/.filesync_test_bindir")"
export PATH="${_bindir}:${PATH}"

failed=()
passed=()
for f in "${selected[@]}"; do
	base="$(basename "${f}")"
	if [[ "${base}" == 01-install-layout.sh ]]; then
		passed+=("${base}")
		continue
	fi
	if [[ "${quiet}" -eq 1 ]]; then
		_tlog="$(mktemp)"
		if env FILESYNC_HOME="${TMP}/sys-${base%.sh}" bash "${f}" >"${_tlog}" 2>&1 </dev/null; then
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
		if env FILESYNC_HOME="${TMP}/sys-${base%.sh}" bash "${f}" </dev/null; then
			passed+=("${base}")
		else
			failed+=("${base}")
		fi
	fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
	echo "run-command-tests: FAILED: ${failed[*]}" >&2
	echo "run-command-tests: passed: ${passed[*]}" >&2
	exit 1
fi
if [[ "${quiet}" -eq 0 ]]; then
	echo "run-command-tests: all passed (${#passed[@]} files)."
fi
