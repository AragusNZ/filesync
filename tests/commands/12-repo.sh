#!/usr/bin/env bash
# Interactive `filesync new repo` — drive prompts via stdin.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/repo-interactive"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	if printf '\n' | filesync new repo 2>/dev/null; then
		die "add-repo should fail when name is empty"
	fi
)

(
	cd "${p}"
	printf '%s\n' '[]' | jq . >"${TMP}/seed-12.json"
	filesync_test_seed_global_repos "$(pwd)" "${TMP}/seed-12.json"
	# Path is derived from cwd vs repo_path_root (seeded above to this directory) → "."
	printf '%s\n' 'ci-repo-name' '' 'https://example.com/r.git' 'main' | filesync new repo
	jq -e '.[] | select(.name=="ci-repo-name" and .url=="https://example.com/r.git" and .path=="." and .branch=="main")' \
		"${FILESYNC_HOME}/repos.json" >/dev/null || die "add-repo should append row to global repos.json"
)
