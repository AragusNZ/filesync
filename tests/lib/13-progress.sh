#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/progress.sh"

if filesync_progress_want 100; then
	bad "want should be false without a TTY stderr"
else
	ok "want false when stderr is not a TTY"
fi

if FILESYNC_NO_PROGRESS=1 filesync_progress_want 100; then
	bad "want should honor FILESYNC_NO_PROGRESS"
else
	ok "FILESYNC_NO_PROGRESS disables want"
fi

_cfg="${LIB_TEST_TMP}/prog_cfg.json"
printf '%s\n' '{"show_progress": false}' >"$_cfg"
if jq -e '.show_progress == false' "$_cfg" >/dev/null; then
	ok "config can express show_progress false"
else
	bad "jq show_progress false"
fi

line="$(COLUMNS=60 filesync_progress_format_line 5 10)"
if [[ "$line" == *' 5/10' ]] && [[ "$line" == '['*'#'* ]]; then
	ok "format_line 5/10 shape"
else
	bad "unexpected format_line: $line"
fi

line2="$(COLUMNS=60 filesync_progress_format_line 10 10)"
if [[ "$line2" == *'10/10' ]]; then
	ok "format_line complete"
else
	bad "unexpected format_line full: $line2"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
