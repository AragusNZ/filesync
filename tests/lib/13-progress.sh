#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/progress.sh"

# Must not rely on the outer script's stderr: interactive runs have -t 2.
if (
	exec 2>/dev/null
	# shellcheck source=/dev/null
	source "${ROOT}/lib/progress.sh"
	filesync_progress_want 100
); then
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
printf '%s\n' '{"progress_display":"hidden"}' >"$_cfg"
if jq -e '.progress_display == "hidden"' "$_cfg" >/dev/null; then
	ok "config can express progress_display hidden"
else
	bad "jq progress_display hidden"
fi

line="$(FILESYNC_PROGRESS_STYLE=bar COLUMNS=60 filesync_progress_format_line 5 10)"
if [[ "$line" == *' 5/10' ]] && [[ "$line" == '['*'#'* ]]; then
	ok "format_line 5/10 shape (bar)"
else
	bad "unexpected format_line: $line"
fi

line2="$(FILESYNC_PROGRESS_STYLE=bar COLUMNS=60 filesync_progress_format_line 10 10)"
if [[ "$line2" == *'10/10' ]]; then
	ok "format_line complete (bar)"
else
	bad "unexpected format_line full: $line2"
fi

linep="$(COLUMNS=60 filesync_progress_format_line 5 10)"
if [[ "$linep" == '[  50% ]' ]]; then
	ok "format_line mid (percent)"
else
	bad "unexpected format_line percent: $linep"
fi

linep2="$(filesync_progress_format_line 1 460)"
if [[ "$linep2" == '[   1% ]' ]]; then
	ok "format_line small slice (percent)"
else
	bad "unexpected format_line percent small: $linep2"
fi

linep3="$(filesync_progress_format_line 460 460)"
if [[ "$linep3" == '[ 100% ]' ]]; then
	ok "format_line done (percent)"
else
	bad "unexpected format_line percent full: $linep3"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
