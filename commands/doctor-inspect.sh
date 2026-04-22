#!/usr/bin/env bash
# filesync doctor inspect: validate catalog and project marker/mapping integrity.
# Usage: filesync doctor [inspect]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync doctor [inspect]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
       filesync doctor inspect

Inspect global catalog consistency and, when in a project, validate files.json rows and marker integrity.
EOF
  exit 0
fi
if [[ $# -gt 0 ]]; then
  filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
  exit 1
fi

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/data-names.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/repos-json.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

repos="$FILESYNC_REPOS_FILE"

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/doctor-format.sh"
filesync_doctor_summary_reset
filesync_doctor_title

filesync_doctor_section "Global catalog"
echo "" >&2
if [[ -n "${FILESYNC_HOME:-}" ]]; then
  filesync_doctor_note_msg "Note: FILESYNC_HOME is set (overrides default ~/.filesync-root)."
else
  filesync_doctor_info "Using default system metadata directory (~/.filesync-root)."
fi
filesync_doctor_info "Effective store: $FILESYNC_SYSTEM_HOME"
if [[ -f "$repos" ]] && jq -e 'type == "array"' "$repos" &>/dev/null; then
  dup_lines="$(filesync_global_repos_duplicate_names "$repos")"
  if [[ -n "$dup_lines" ]]; then
    filesync_doctor_warn_msg "Warning: duplicate repo name(s) in repos.json (behavior is ambiguous until fixed):"
    while IFS= read -r line; do
      filesync_doctor_detail "$line"
    done <<<"$dup_lines"
  else
    filesync_doctor_info "Global repos.json: no duplicate repo names."
  fi
  rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"
  path_lines="$(filesync_global_repos_missing_checkout_lines "$repos" "$rroot")"
  if [[ -n "$path_lines" ]]; then
    filesync_doctor_warn_msg "Warning: repo checkout path missing or not a directory:"
    while IFS= read -r line; do
      filesync_doctor_detail "$line"
    done <<<"$path_lines"
  else
    filesync_doctor_info "Global repos.json: all checkout directories exist."
  fi
fi
echo "" >&2

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/resolve.sh"
if filesync_try_resolve_project; then
  export FILESYNC_FILES_FILE="${FILESYNC_DIR}/${FILESYNC_FILES_NAME}"
  # shellcheck source=/dev/null
  source "$_CMD_ROOT/../lib/doctor-project.sh"
  filesync_doctor_section "Project ($(basename "$PROJECT_ROOT"))"
  echo "" >&2
  filesync_doctor_project_files_json_sanity
  echo "" >&2
  _doctor_state_cleanup() { rm -f "${FILESYNC_STATE_FILE:-}"; }
  if filesync_try_command_init "${BASH_SOURCE[0]}"; then
    filesync_doctor_project_clone_markers_vs_rows
    echo "" >&2
    filesync_doctor_project_orphan_clone_markers
    echo "" >&2
    filesync_doctor_project_scan_master_markers
    _doctor_state_cleanup
  else
    filesync_doctor_note_msg "Note: Skipping clone and master file scans (project state could not be loaded)."
  fi
else
  filesync_doctor_note_msg "Skipping project-local scans (not in a filesync project)."
fi
filesync_doctor_summary_print
