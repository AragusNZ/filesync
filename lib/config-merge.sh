#!/usr/bin/env bash
# Merge package default config with user .filesync/config.json (shallow).

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data-names.sh"

# Requires: FILESYNC_PKG_ROOT, FILESYNC_DIR
# Prints merged JSON object (no repos/files) to stdout.
filesync_merged_top_level_config() {
  local def="${FILESYNC_PKG_ROOT}/share/defaults/config.default.json"
  local ucfg="${FILESYNC_DIR}/${FILESYNC_CONFIG_NAME}"
  local user_json
  if [[ -f "$ucfg" ]]; then
    user_json="$(cat "$ucfg")"
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
    | del(.show_progress, .enabled)
  ' "$def" <(echo "$user_json")
}
