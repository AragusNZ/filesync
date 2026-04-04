#!/usr/bin/env bash
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

master="${TMP}/info-master" proj_a="${TMP}/info-proj-a" proj_b="${TMP}/info-proj-b"
rm -rf "${master}" "${proj_a}" "${proj_b}"

mkdir -p "${master}" "${proj_a}" "${proj_b}"
master="$(cd "${master}" && pwd -P)"
proj_a="$(cd "${proj_a}" && pwd -P)"
proj_b="$(cd "${proj_b}" && pwd -P)"
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

(
	cd "${proj_b}"
	filesync init
)

(
	cd "${proj_a}"
	filesync init
	jq -n \
		--arg master "${master}" \
		--arg b "${proj_b}" \
		'[
			{"name":"emissions","path":$master,"url":null,"branch":"main"},
			{"name":"greenlit-api","path":$b,"url":null,"branch":null}
		]' >"${TMP}/seed-33.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-33.json"
	filesync add emissions tools/x.txt --also=greenlit-api
)

_out="$(cd "${proj_a}" && filesync info file tools/x.txt 2>&1)" || _ec=$?
[[ "${_ec:-0}" -eq 0 ]] || die "info file should exit 0, got ${_ec}: ${_out}"
[[ "${_out}" == *"Role: clone"* ]] || die "info file on clone path should print Role: clone"
[[ "${_out}" == *"Current project row"* ]] || die "info file clone path should print current row hint"
[[ "${_out}" == *"${proj_a}"* ]] || die "info output should mention proj_a (${proj_a})"
[[ "${_out}" == *"${proj_b}"* ]] || die "info output should mention proj_b (${proj_b})"

_out_i="$(cd "${proj_a}" && filesync i tools/x.txt 2>&1)" || _ec2=$?
[[ "${_ec2:-0}" -eq 0 ]] || die "i <path> (no file/-f) should exit 0, got ${_ec2}: ${_out_i}"
[[ "${_out_i}" == *"${proj_b}"* ]] || die "i <path> should list sibling project"

# Master-at-checkout with no tracked clones: strip kind=master when --fix-marker
solo="${TMP}/info-solo-master"
rm -rf "${solo}"
mkdir -p "${solo}/tools"
solo="$(cd "${solo}" && pwd -P)"
(
	cd "${solo}"
	git init -b main
	git config user.email ci@test
	git config user.name ci
	filesync init
	{
		echo "solo-only"
		echo "# filesync kind=master"
	} >tools/only.txt
	git add tools/only.txt
	git commit -q -m init
	jq -n \
		--arg p "$(pwd)" \
		'[{"name":"solo","path":$p,"url":null,"branch":"main"}]' >"${TMP}/seed-33solo.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-33solo.json"
	_out_solo="$(filesync info file tools/only.txt 2>&1)" || die "info file solo master: ${_out_solo}"
	[[ "${_out_solo}" == *"Role: master"* ]] || die "info file on master path should print Role: master"
	[[ "${_out_solo}" == *"Clones below:"* ]] || die "info file master path should print clone-list hint"
	filesync info file tools/only.txt --fix-marker >/dev/null 2>&1 \
		|| die "info file --fix-marker (strip) should succeed"
)
if grep -qE 'filesync kind=master' "${solo}/tools/only.txt"; then
	die "master marker should have been stripped (no clones)"
fi
grep -q 'solo-only' "${solo}/tools/only.txt" || die "content should remain after strip"
