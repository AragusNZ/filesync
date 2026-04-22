#!/usr/bin/env bash
# Inspect or change system-level filesync settings (preferences). Repo flags: edit repo.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync config show | set progress <hidden|bar|percent>'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
Usage:
  filesync config show
  filesync config set progress <hidden|bar|percent>

Inspect or change user-wide filesync settings (not per-repo flags).

Commands:

  show
    Print where data lives, resolved paths, and current preferences (ends with a one-line summary).

  set progress <hidden|bar|percent>
    Change how progress is shown during long scans (for example sync/check).

Related:
  Per-repo behavior (check on sync, mirror-in, merge_using_git): filesync edit repo -h
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
