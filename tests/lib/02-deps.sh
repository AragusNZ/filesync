#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/deps.sh"

filesync_require_jq && ok "require_jq" || bad "require_jq"
filesync_require_git && ok "require_git" || bad "require_git"

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
