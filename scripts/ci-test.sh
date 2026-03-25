#!/usr/bin/env bash
# Full project test suite: command tests (staged install + CLI) then library tests.
# Usage: from repo root — bash scripts/ci-test.sh [--quiet|-q]
#        FILESYNC_TEST_QUIET=1  suppresses passing output (same as --quiet).
set -euo pipefail

ROOT="$(cd "$(dirname "${0}")/.." && pwd)"

suppress_pass_msg="${FILESYNC_TEST_QUIET:-0}"
[[ "${suppress_pass_msg}" == "1" ]] || suppress_pass_msg=0
for _arg in "$@"; do
	case "${_arg}" in
		--quiet|-q) suppress_pass_msg=1 ;;
	esac
done

bash "${ROOT}/tests/run-command-tests.sh" "$@" "${ROOT}"
bash "${ROOT}/tests/run-lib-tests.sh" "$@" "${ROOT}"
if [[ "${suppress_pass_msg}" -eq 0 ]]; then
	echo "All ci-test.sh cases passed."
fi
