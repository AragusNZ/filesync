#!/usr/bin/env bash
# Merge package default preferences with user preferences.json in system home (shallow).

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data-names.sh"

# Requires: FILESYNC_PKG_ROOT, FILESYNC_SYSTEM_HOME
# Prints merged JSON object to stdout.
filesync_merged_preferences() {
  local def="${FILESYNC_PKG_ROOT}/share/defaults/preferences.default.json"
  local uprefs="${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"
  local user_json
  if [[ -f "$uprefs" ]]; then
    user_json="$(cat "$uprefs")"
  else
    user_json="{}"
  fi
  jq -s '
    .[0] * .[1]
    | .progress_display = (
        .progress_display
        | if type == "string" and (. == "hidden" or . == "bar" or . == "percent") then .
          else "percent" end
      )
  ' "$def" <(echo "$user_json")
}
