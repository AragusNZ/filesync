#!/usr/bin/env bash
# Merge package default preferences with user preferences.json in system home (shallow).

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data-names.sh"

# Requires: FILESYNC_PKG_ROOT, FILESYNC_SYSTEM_HOME
# Prints merged JSON object to stdout.
#
# User preferences must be a JSON object (e.g. {}). Top-level null, arrays, strings, invalid JSON,
# or an empty file are treated as {} so merge never fails with jq object*null.
filesync_merged_preferences() {
  local def="${FILESYNC_PKG_ROOT}/share/defaults/preferences.default.json"
  local uprefs="${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"
  local rawpath="/dev/null"
  [[ -f "$uprefs" ]] && rawpath="$uprefs"

  jq -n \
    --slurpfile def "$def" \
    --rawfile ur "$rawpath" \
    '
    ($def[0] // {} | if type != "object" then {} else . end) as $base |
    (try (
        if ($ur | length) == 0 then {}
        else ($ur | fromjson)
        end
      ) catch {}) as $parsed |
    (if ($parsed | type) == "object" then $parsed else {} end) as $u |
    $base * $u
    | .progress_display = (
        .progress_display
        | if type == "string" and (. == "hidden" or . == "bar" or . == "percent") then .
          else "percent" end
      )
    '
}
