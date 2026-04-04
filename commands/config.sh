#!/usr/bin/env bash
# Inspect or change system-level filesync settings (preferences). Repo flags: edit repo.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync config show | doctor | set progress <hidden|bar|percent>'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
Usage:
  filesync config show
  filesync config doctor
  filesync config set progress <hidden|bar|percent>

show    Effective system home, repo path anchor, global JSON paths, preferences.
doctor  Report global catalog issues and (from a project) files.json sanity, clone marker vs rows, orphan clone markers, and master markers without tracked clones. Sections and a summary of warnings/notes.
set     progress (preferences.json).

Per-repo check_sync_enabled / mirror_in_enabled: use filesync edit repo (see filesync edit repo -h).
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/data-names.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/preferences-merge.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/fs-lock.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/repos-json.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

sys="${FILESYNC_SYSTEM_HOME}/${FILESYNC_SYSTEM_NAME}"
repos="$FILESYNC_REPOS_FILE"
prefs="${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"

if [[ $# -lt 1 ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

cmd="$1"
shift

case "$cmd" in
  show)
    echo "System metadata directory: $FILESYNC_SYSTEM_HOME" >&2
    if [[ -n "${FILESYNC_HOME:-}" ]]; then
      echo "Note: FILESYNC_HOME is set (overrides default ~/.filesync-root)." >&2
    fi
    echo "Repo path anchor (relative paths in repos.json): $(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")" >&2
    if [[ -n "${FILESYNC_REPO_PATH_ANCHOR:-}" ]]; then
      echo "Note: FILESYNC_REPO_PATH_ANCHOR overrides the anchor (tests / automation)." >&2
    fi
    echo "system.json: $sys" >&2
    echo "Global repos: $repos" >&2
    echo "Global collections: $FILESYNC_COLLECTIONS_FILE" >&2
    echo "Preferences (effective progress_display): $(filesync_merged_preferences | jq -r '.progress_display')" >&2
    ;;
  doctor)
    # shellcheck source=/dev/null
    source "$_CMD_ROOT/../lib/config-doctor-format.sh"
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
      source "$_CMD_ROOT/../lib/config-doctor-project.sh"
      filesync_doctor_section "Project ($(basename "$PROJECT_ROOT"))"
      echo "" >&2
      filesync_config_doctor_files_json_sanity
      echo "" >&2
      _doctor_state_cleanup() { rm -f "${FILESYNC_STATE_FILE:-}"; }
      if filesync_try_command_init "${BASH_SOURCE[0]}"; then
        filesync_config_doctor_clone_markers_vs_rows
        echo "" >&2
        filesync_config_doctor_orphan_clone_markers
        echo "" >&2
        filesync_config_doctor_scan_master_markers
        _doctor_state_cleanup
      else
        filesync_doctor_note_msg "Note: Skipping clone and master file scans (project state could not be loaded)."
      fi
    else
      filesync_doctor_note_msg "Skipping project-local scans (not in a filesync project)."
    fi
    filesync_doctor_summary_print
    ;;
  set)
    [[ $# -ge 2 ]] || {
      filesync_usage_error_stderr 'Usage: filesync config set progress <hidden|bar|percent>'
      exit 1
    }
    what="$1"
    shift
    case "$what" in
      system-home)
        echo -e "${RED}config set system-home is removed. The system store is always ~/.filesync-root, or FILESYNC_HOME when set (tests/automation only).${NC}" >&2
        echo "Do not set FILESYNC_HOME in per-project .env; use one catalog per machine." >&2
        exit 1
        ;;
      repo-path-root)
        echo -e "${RED}repo-path-root is no longer configurable; relative repo paths use your home directory.${NC}" >&2
        echo "For tests, set FILESYNC_REPO_PATH_ANCHOR to an absolute directory." >&2
        exit 1
        ;;
      progress)
        [[ $# -eq 1 ]] || exit 1
        m="$1"
        case "$m" in hidden | bar | percent) ;;
        *) echo -e "${RED}progress must be hidden, bar, or percent${NC}" >&2; exit 1 ;;
        esac
        filesync_global_lock_acquire
        trap 'filesync_global_lock_release' EXIT
        mkdir -p "$(dirname "$prefs")"
        [[ -f "$prefs" ]] || echo '{}' | jq . >"$prefs"
        jq --arg m "$m" '.progress_display = $m' "$prefs" >"${prefs}.tmp"
        mv "${prefs}.tmp" "$prefs"
        filesync_global_lock_release
        trap - EXIT
        echo -e "${GREEN}progress_display set to $m${NC}" >&2
        ;;
      *)
        echo -e "${RED}Unknown set target: $what${NC}" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo -e "${RED}Unknown config subcommand: $cmd${NC}" >&2
    filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
    exit 1
    ;;
esac
