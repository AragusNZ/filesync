#!/usr/bin/env bash
# Standard init for filesync commands (after set -euo pipefail in caller).

filesync_command_init_lite() {
  local script_path="${1:?}"
  FILESYNC_PKG_ROOT="$(cd "$(dirname "$script_path")/.." && pwd)"
  export FILESYNC_PKG_ROOT

  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/colors.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/deps.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/resolve.sh"

  filesync_resolve_or_exit
  filesync_require_jq
}

filesync_command_init() {
  local script_path="${1:?}"
  FILESYNC_PKG_ROOT="$(cd "$(dirname "$script_path")/.." && pwd)"
  export FILESYNC_PKG_ROOT

  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/colors.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/deps.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/scripts-dir.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/resolve.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/config-merge.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/paths.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/file-filter.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/json-state.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/markers.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/status.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/repo-resolve.sh"

  filesync_resolve_or_exit
  filesync_require_files
  filesync_export_data_paths

  filesync_require_jq

  FILESYNC_STATE_FILE=$(mktemp)
  filesync_assemble_state_to "$FILESYNC_STATE_FILE" || exit 1

  CONFIG_FILE="$FILESYNC_STATE_FILE"
  export CONFIG_FILE FILESYNC_STATE_FILE PROJECT_ROOT FILESYNC_DIR \
    FILESYNC_FILES_FILE FILESYNC_REPOS_FILE FILESYNC_USER_CONFIG

  PATH_MODE=$(jq -r '.path_mode // "relative"' "$CONFIG_FILE")
  export PATH_MODE
}
