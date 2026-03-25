#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
# shellcheck source=/dev/null
source "${ROOT}/lib/marker-style.sh"

if filesync_marker_style_valid "html" && ! filesync_marker_style_valid "nope"; then ok "marker_style_valid"; else bad "marker_style_valid"; fi
if [[ "$(filesync_marker_style_for_path "x.css")" == "block_c" ]]; then ok "marker_style css"; else bad "css style"; fi
if [[ "$(filesync_marker_style_for_path "q.sql")" == "line_dash" ]]; then ok "marker_style sql"; else bad "sql style"; fi
if [[ "$(filesync_marker_style_for_path "a.js")" == "line_slash" ]]; then ok "marker_style js"; else bad "js style"; fi
if [[ "$(filesync_marker_style_for_path "unknown.bin")" == "line_hash" ]]; then ok "marker_style default hash"; else bad "default style"; fi
if [[ "$(filesync_marker_style_resolve "x.css" "bogus")" == "block_c" ]]; then ok "marker_style_resolve invalid override"; else bad "invalid override"; fi
if [[ "$(filesync_marker_style_resolve "x.py" "line_slash")" == "line_slash" ]]; then ok "marker_style_resolve override"; else bad "override"; fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
