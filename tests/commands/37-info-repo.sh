#!/usr/bin/env bash
# filesync info repo: catalog, checkout check, project file counts / status summary.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/ir-master" proj="${TMP}/ir-proj"
rm -rf "${master}" "${proj}"

mkdir -p "${master}"
(
	cd "${master}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	filesync init
	mkdir -p tools
	{
		echo "BODY"
		echo "# filesync kind=master"
	} >tools/x.txt
	git add tools/x.txt
	git commit -q -m init
)

mkdir -p "${proj}"
(
	cd "${proj}"
	filesync init
	jq -n \
		--arg mp "${master}" \
		'[{"name":"emissions","path":$mp,"url":null,"branch":"main"}]' >"${TMP}/seed-ir.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-ir.json"
	filesync add emissions tools/x.txt
)

_out="$(cd "${proj}" && filesync info repo emissions 2>&1)" || _ec=$?
[[ "${_ec:-0}" -eq 0 ]] || die "info repo should exit 0, got ${_ec}: ${_out}"
echo "$_out" | grep -qF 'Checkout directory exists' || die "expected checkout ok message"
echo "$_out" | grep -qF 'File rows linked to this repo: 1' || die "expected one file row"
echo "$_out" | grep -qF 'Status summary' || die "expected status summary"

_out_r="$(cd "${proj}" && filesync i -r emissions 2>&1)" || _ecr=$?
[[ "${_ecr:-0}" -eq 0 ]] || die "i -r should exit 0, got ${_ecr}: ${_out_r}"
echo "$_out_r" | grep -qF 'emissions' || die "i -r should mention repo name"

if filesync info repo 2>/dev/null; then
	die "info repo without name should fail"
fi

if filesync info repo nosuchrepo 2>/dev/null; then
	die "info repo unknown name should fail"
fi

ghost_proj="${TMP}/ir-ghost-proj"
mkdir -p "${ghost_proj}" "${TMP}/ir-bad-anchor"
(
	cd "${ghost_proj}"
	filesync init
	jq -n \
		'[{"name":"ghost","path":"absolutely-not-there-ir","url":null,"branch":"main"}]' >"${TMP}/seed-ir-ghost.json"
	filesync_test_seed_global_repos "${TMP}/ir-bad-anchor" "${TMP}/seed-ir-ghost.json"
)
_out_g="$(cd "${ghost_proj}" && filesync info repo ghost 2>&1)" || _ecg=$?
[[ "${_ecg:-0}" -eq 0 ]] || die "info repo ghost should exit 0 with warning, got ${_ecg}: ${_out_g}"
echo "$_out_g" | grep -qF 'Warning: checkout path missing' || die "expected missing-checkout warning"
