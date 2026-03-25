#!/usr/bin/env bash
# Interactive `filesync add-repo` — drive prompts via stdin.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

p="${TMP}/repo-interactive"
mkdir -p "${p}"
(
	cd "${p}"
	filesync init
	rm -f .filesync/repos.json
	if printf '\n' | filesync add-repo 2>/dev/null; then
		die "add-repo should fail when repos.json missing"
	fi
)

(
	cd "${p}"
	filesync init
	printf '%s\n' 'ci-repo-name' 'https://example.com/r.git' '../checkout' 'main' | filesync add-repo
	jq -e '.[] | select(.name=="ci-repo-name" and .url=="https://example.com/r.git" and .path=="../checkout" and .branch=="main")' \
		".filesync/repos.json" >/dev/null || die "add-repo should append row to repos.json"
)
