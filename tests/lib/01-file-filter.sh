#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/file-filter.sh"

if filesync_file_matches_fragment "" "a" "b"; then ok "empty fragment matches"; else bad "empty fragment"; fi
if filesync_file_matches_fragment "foo" "x/foo" "y"; then ok "fragment in local_path"; else bad "local_path match"; fi
if filesync_file_matches_fragment "bar" "a" "z/bar/b"; then ok "fragment in repo_file_path"; else bad "repo_path match"; fi
if ! filesync_file_matches_fragment "zzz" "a" "b"; then ok "non-match"; else bad "should not match"; fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
