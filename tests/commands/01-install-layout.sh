#!/usr/bin/env bash
# Two PREFIX layouts (/usr/local and /usr), man page, init/help/version smoke.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

prefix_smoke() {
	local label="$1" dest="$2" prefix="$3"
	mkdir -p "${dest}"
	make -C "${ROOT}" install DESTDIR="${dest}" PREFIX="${prefix}"
	local fs
	fs="$(PATH="${dest}${prefix}/bin:${PATH}" command -v filesync)"
	readlink -f "${fs}" | grep -q 'lib/filesync' || die "filesync not resolved under lib/filesync (${fs}) (${label})"
	local _m
	_m="$(MANPATH="${dest}${prefix}/share/man" PATH="${dest}${prefix}/bin:${PATH}" man filesync 2>&1)" || die "man filesync (${label})"
	[[ "${_m}" == *filesync* ]] || die "man filesync body (${label})"
	mkdir -p "${TMP}/proj-${label}"
	(
		cd "${TMP}/proj-${label}"
		PATH="${dest}${prefix}/bin:${PATH}" filesync init
		[[ -f .filesync/config.json && -f .filesync/repos.json && -f .filesync/files.json ]] || die "init missing json (${label})"
		[[ "$(PATH="${dest}${prefix}/bin:${PATH}" filesync help 2>&1)" == *filesync* ]] || die "help (${label})"
		PATH="${dest}${prefix}/bin:${PATH}" filesync check >/dev/null || die "check empty project (${label})"
		[[ "$(PATH="${dest}${prefix}/bin:${PATH}" filesync --version 2>&1)" == *"filesync ${EXPECTED_VERSION}"* ]] || die "--version (${label})"
		[[ "$(PATH="${dest}${prefix}/bin:${PATH}" filesync -V 2>&1)" == *"filesync ${EXPECTED_VERSION}"* ]] || die "-V (${label})"
	)
}

prefix_smoke local "${TMP}/stage-local" /usr/local
prefix_smoke usr "${TMP}/stage-usr" /usr

printf '%s\n' "${TMP}/stage-local/usr/local/bin" >"${TMP}/.filesync_test_bindir"
