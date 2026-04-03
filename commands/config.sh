#!/usr/bin/env bash
# Inspect or change system-level filesync settings (store path, preferences, repo flags).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage:
  filesync config show
  filesync config doctor
  filesync config set system-home <absolute_dir>
  filesync config set progress <hidden|bar|percent>
  filesync config repo <name> check-sync <true|false>
  filesync config repo <name> mirror-in <true|false>

show    Effective system home, pointer, repo path anchor, global JSON paths, preferences.
doctor  Report pointer validity, FILESYNC_HOME override, and duplicate repo names in repos.json.
set     system-home (pointer file) or progress (preferences.json).
repo    Toggle per-repo flags in global repos.json.
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
ptr="$(filesync_system_home_pointer_path)"

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: filesync config show | doctor | set ... | repo ...${NC}" >&2
  exit 1
fi

cmd="$1"
shift

case "$cmd" in
  show)
    echo "FILESYNC_HOME (effective): $FILESYNC_SYSTEM_HOME" >&2
    echo "Pointer file: $ptr" >&2
    if [[ -n "${FILESYNC_HOME:-}" ]]; then
      echo "Note: FILESYNC_HOME is set in the environment (overrides pointer and default)." >&2
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
    if [[ -n "${FILESYNC_HOME:-}" ]]; then
      echo "FILESYNC_HOME is set; metadata directory is isolated from the pointer file." >&2
    fi
    if [[ -f "$ptr" ]]; then
      line="$(tr -d '\r\n' <"$ptr")"
      if [[ -n "$line" ]] && [[ ! -d "$line" ]]; then
        echo "Pointer file lists a non-directory (ignored at runtime): $line" >&2
      else
        echo "Pointer file: OK" >&2
      fi
    else
      echo "No pointer file (using default ~/.filesync-root unless FILESYNC_HOME is set)." >&2
    fi
    echo "Effective store: $FILESYNC_SYSTEM_HOME" >&2
    if [[ -f "$repos" ]] && jq -e 'type == "array"' "$repos" &>/dev/null; then
      dup_lines="$(filesync_global_repos_duplicate_names "$repos")"
      if [[ -n "$dup_lines" ]]; then
        echo "Warning: duplicate repo name(s) in repos.json (behavior is ambiguous until fixed):" >&2
        while IFS= read -r line; do
          echo "  $line" >&2
        done <<<"$dup_lines"
      else
        echo "Global repos.json: no duplicate repo names." >&2
      fi
    fi
    ;;
  set)
    [[ $# -ge 2 ]] || { echo -e "${RED}Usage: filesync config set system-home|progress ...${NC}" >&2; exit 1; }
    what="$1"
    shift
    case "$what" in
      system-home)
        [[ $# -eq 1 ]] || exit 1
        [[ -d "$1" ]] || { echo -e "${RED}Not a directory: $1${NC}" >&2; exit 1; }
        filesync_write_system_home_pointer "$1"
        echo -e "${GREEN}Pointer updated. Effective FILESYNC_HOME: $(filesync_system_home_dir)${NC}" >&2
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
  repo)
    [[ $# -ge 3 ]] || {
      echo -e "${RED}Usage: filesync config repo <name> check-sync|mirror-in <true|false>${NC}" >&2
      exit 1
    }
    rname="$1"
    flag="$2"
    val_raw="$3"
    case "${val_raw,,}" in
      true | 1 | yes) vjson=true ;;
      false | 0 | no) vjson=false ;;
      *)
        echo -e "${RED}Expected true or false, got: $val_raw${NC}" >&2
        exit 1
        ;;
    esac
    jq -e --arg n "$rname" 'any(.name == $n)' "$repos" &>/dev/null || {
      echo -e "${RED}No repo named '$rname'${NC}" >&2
      exit 1
    }
    filesync_global_lock_acquire
    trap 'filesync_global_lock_release' EXIT
    tmp="$(mktemp)"
    case "$flag" in
      check-sync)
        jq --arg n "$rname" --argjson v "$vjson" 'map(if .name == $n then .check_sync_enabled = $v else . end)' "$repos" >"$tmp"
        ;;
      mirror-in)
        jq --arg n "$rname" --argjson v "$vjson" 'map(if .name == $n then .mirror_in_enabled = $v else . end)' "$repos" >"$tmp"
        ;;
      *)
        echo -e "${RED}Unknown flag: $flag (use check-sync or mirror-in)${NC}" >&2
        rm -f "$tmp"
        filesync_global_lock_release
        trap - EXIT
        exit 1
        ;;
    esac
    mv "$tmp" "$repos"
    filesync_global_lock_release
    trap - EXIT
    echo -e "${GREEN}Updated repo '$rname': $flag = $vjson${NC}" >&2
    ;;
  *)
    echo -e "${RED}Unknown config subcommand: $cmd${NC}" >&2
    exit 1
    ;;
esac
