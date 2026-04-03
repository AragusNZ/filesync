#!/usr/bin/env bash
# Repo path anchor: fixed (HOME or FILESYNC_REPO_PATH_ANCHOR); config show reports it.
set -euo pipefail
: "${ROOT:?}" "${TMP:?}" "${EXPECTED_VERSION:?}"
# shellcheck source=/dev/null
source "${ROOT}/tests/harness-command.sh"

sub="${TMP}/16-anchor-sub"
mkdir -p "${sub}"
export FILESYNC_HOME="${TMP}/fsys-16-anchor"
export FILESYNC_REPO_PATH_ANCHOR="${sub}"

out="$(filesync config show 2>&1)" || die "config show"
echo "$out" | grep -qF 'Repo path anchor' || die "config show should mention anchor"
echo "$out" | grep -qF "${sub}" || die "config show should list FILESYNC_REPO_PATH_ANCHOR"

if filesync config set repo-path-root /tmp 2>/dev/null; then
	die "repo-path-root should be rejected"
fi
