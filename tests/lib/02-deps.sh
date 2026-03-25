#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/log.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/deps.sh"

if filesync_require_jq; then ok "require_jq"; else bad "require_jq"; fi
if filesync_require_git; then ok "require_git"; else bad "require_git"; fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
