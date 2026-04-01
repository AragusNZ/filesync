#!/usr/bin/env bash
# Remove mapping from .filesync/files.json; strip clone/detached marker from local file (keep kind=master).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync remove-file [--all-missing] [<local_path> ...]
Alias: rmf

Drop the row from .filesync/files.json; strip clone/detached markers from the local file;
keep kind=master when present.

  --all-missing        Also remove every mapping whose sync_status is error_missing_master
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/rm-mapping.sh"

trap 'filesync_progress_end || true; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

ALL_MISSING=false
declare -a POSITIONAL_PATHS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --all-missing)
      ALL_MISSING=true
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync rmf|remove-file [--all-missing] [<local_path1> [local_path2 ...]]" >&2
      exit 1
      ;;
    *)
      POSITIONAL_PATHS+=("$1")
      shift
      ;;
  esac
done

declare -a LOCAL_PATHS=()
declare -A SEEN_LOCAL_PATHS=()

for arg in "${POSITIONAL_PATHS[@]}"; do
  [[ -n "$arg" ]] || { echo -e "${RED}Error: empty local_path${NC}" >&2; exit 1; }
  [[ -z "${SEEN_LOCAL_PATHS[$arg]:-}" ]] || { echo -e "${RED}Error: duplicate '$arg'${NC}" >&2; exit 1; }
  SEEN_LOCAL_PATHS["$arg"]=1
  LOCAL_PATHS+=("$arg")
done

if [[ "$ALL_MISSING" == true ]]; then
  while IFS= read -r _lp; do
    [[ -z "$_lp" || "$_lp" == "null" ]] && continue
    if [[ -z "${SEEN_LOCAL_PATHS[$_lp]:-}" ]]; then
      SEEN_LOCAL_PATHS["$_lp"]=1
      LOCAL_PATHS+=("$_lp")
    fi
  done < <(jq -r '.[] | select(.sync_status == "error_missing_master" and (.local_path | type == "string") and (.local_path | length > 0)) | .local_path' "$FILESYNC_FILES_FILE")
fi

if [[ ${#LOCAL_PATHS[@]} -eq 0 ]]; then
  if [[ "$ALL_MISSING" == true ]]; then
    echo "filesync rmf: no error_missing_master rows to remove." >&2
    exit 0
  fi
  echo -e "${RED}Usage: filesync rmf|remove-file [--all-missing] [<local_path1> [local_path2 ...]]${NC}" >&2
  exit 1
fi

_rpaths=${#LOCAL_PATHS[@]}
if filesync_progress_want "$_rpaths"; then
  filesync_progress_begin "$_rpaths"
fi
_rpi=0

for lp in "${LOCAL_PATHS[@]}"; do
  filesync_remove_file_mapping_row "$PROJECT_ROOT" "$FILESYNC_FILES_FILE" "$lp" || filesync_die "remove failed for one or more paths (see messages above)"
  _rpi=$((_rpi + 1))
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    filesync_progress_update "$_rpi"
  fi
done

filesync_progress_end
