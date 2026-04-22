#!/usr/bin/env bash
# Standard init for filesync commands (after set -euo pipefail in caller).

# Shared by filesync_command_init_* (colors, log, deps).
_filesync_source_core_libs() {
  local pkg_root="${1:?}"
  # shellcheck source=/dev/null
  source "$pkg_root/lib/colors.sh"
  # shellcheck source=/dev/null
  source "$pkg_root/lib/log.sh"
  # shellcheck source=/dev/null
  source "$pkg_root/lib/deps.sh"
}

filesync_command_init_lite() {
  local script_path="${1:?}"
  FILESYNC_PKG_ROOT="$(cd "$(dirname "$script_path")/.." && pwd)"
  export FILESYNC_PKG_ROOT

  _filesync_source_core_libs "$FILESYNC_PKG_ROOT"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/resolve.sh"

  filesync_resolve_or_exit
  filesync_require_jq
  filesync_log_enable_debug
}

# System metadata only (no project .filesync required). Sets FILESYNC_SYSTEM_HOME.
filesync_command_init_system() {
  local script_path="${1:?}"
  FILESYNC_PKG_ROOT="$(cd "$(dirname "$script_path")/.." && pwd)"
  export FILESYNC_PKG_ROOT

  _filesync_source_core_libs "$FILESYNC_PKG_ROOT"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/system-resolve.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/data-names.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/repos-json.sh"

  filesync_require_jq
  filesync_log_enable_debug

  FILESYNC_SYSTEM_HOME="$(filesync_ensure_system_store)" || filesync_die "could not initialize system filesync store"
  export FILESYNC_SYSTEM_HOME
  export FILESYNC_REPOS_FILE="${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"
  export FILESYNC_COLLECTIONS_FILE="${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_COLLECTIONS_NAME}"
  filesync_assert_global_repos_have_merge_using_git "$FILESYNC_REPOS_FILE" || filesync_die "invalid global repos (see message above)"
}

# Args: script_path, files_policy require|optional, assemble_on_fail die|return
# optional: skip files.json with return 1 (no stderr) when missing. return: rm temp state on assemble failure.
_filesync_command_init_project_full() {
  local script_path="${1:?}"
  local files_policy="${2:?}"
  local assemble_on_fail="${3:?}"

  FILESYNC_PKG_ROOT="$(cd "$(dirname "$script_path")/.." && pwd)"
  export FILESYNC_PKG_ROOT

  _filesync_source_core_libs "$FILESYNC_PKG_ROOT"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/resolve.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/paths.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/project-context.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/file-filter.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/json-state.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/markers.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/status.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/report.sh"
  # shellcheck source=/dev/null
  source "$FILESYNC_PKG_ROOT/lib/repo-resolve.sh"

  filesync_resolve_or_exit
  if [[ "$files_policy" == require ]]; then
    filesync_require_files
  else
    [[ -f "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" ]] || return 1
  fi

  FILESYNC_SYSTEM_HOME="$(filesync_ensure_system_store)" || filesync_die "could not initialize system filesync store"
  export FILESYNC_SYSTEM_HOME

  filesync_export_data_paths

  filesync_require_jq
  filesync_require_git
  filesync_log_enable_debug

  FILESYNC_STATE_FILE=$(mktemp)
  if [[ "$assemble_on_fail" == die ]]; then
    filesync_assemble_state_to "$FILESYNC_STATE_FILE" || filesync_die "could not load project configuration (see messages above)"
  else
    if ! filesync_assemble_state_to "$FILESYNC_STATE_FILE"; then
      rm -f "$FILESYNC_STATE_FILE"
      unset FILESYNC_STATE_FILE
      return 1
    fi
  fi

  CONFIG_FILE="$FILESYNC_STATE_FILE"
  export CONFIG_FILE FILESYNC_STATE_FILE PROJECT_ROOT FILESYNC_DIR \
    FILESYNC_FILES_FILE FILESYNC_REPOS_FILE FILESYNC_COLLECTIONS_FILE FILESYNC_SYSTEM_HOME

  REPO_PATH_ROOT=$(jq -r '.repo_path_root' "$CONFIG_FILE")
  export REPO_PATH_ROOT

  if [[ -n "${FILESYNC_VERBOSE:-}" && -n "${FILESYNC_HOME:-}" ]]; then
    echo "filesync: using FILESYNC_HOME=${FILESYNC_SYSTEM_HOME} (metadata directory override)" >&2
  fi
  return 0
}

filesync_command_init() {
  _filesync_command_init_project_full "${1:?}" require die
}

# Same as filesync_command_init but returns 1 when state cannot be assembled (e.g. invalid files.json
# repo_id). Cleans up temp state file on failure. Used by doctor inspect after lightweight JSON checks.
filesync_try_command_init() {
  _filesync_command_init_project_full "${1:?}" optional return
}
