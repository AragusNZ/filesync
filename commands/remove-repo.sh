#!/usr/bin/env bash
# Remove a repo from repos.json when it has no file rows, or after confirming, unmap all its files first (same as rmf).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync remove-repo <repo_name> [-y|--yes]
Alias: rmr

Remove a repo from repos.json when it has no file rows, or after confirmation unmap all
its files (same as remove-file per row).

  -y, --yes   Skip the prompt when file mappings still exist

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

YES=0
REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      YES=1
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync remove-repo|rmr <repo_name> [-y]" >&2
      exit 1
      ;;
    *)
      if [[ -n "$REPO" ]]; then
        echo -e "${RED}Unexpected argument: $1${NC}" >&2
        echo "Usage: filesync remove-repo|rmr <repo_name> [-y]" >&2
        exit 1
      fi
      REPO="$1"
      shift
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo -e "${RED}Usage: filesync remove-repo|rmr <repo_name> [-y]${NC}" >&2
  exit 1
fi

repos="$FILESYNC_REPOS_FILE"
files="$FILESYNC_FILES_FILE"

if ! jq -e --arg c "$REPO" 'any(.name == $c)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$REPO' not found in repos.${NC}" >&2
  exit 1
fi

count=$(jq --arg r "$REPO" '[.[] | select(.repo_name == $r)] | length' "$files")

remove_repo_entry() {
  jq --arg n "$REPO" 'map(select(.name != $n))' "$repos" > "${repos}.tmp"
  mv "${repos}.tmp" "$repos"
  echo -e "${GREEN}Removed repo:${NC} $REPO" >&2
}

if [[ "$count" -eq 0 ]]; then
  remove_repo_entry
  filesync_progress_end
  exit 0
fi

echo -e "${YELLOW}Repo '$REPO' has ${count} file mapping(s) in files.json.${NC}" >&2
if [[ "$YES" -ne 1 ]]; then
  read -rp "Are you sure you want to remove this repo? Doing so will also remove all associated files. [y/N] " ans || true
  if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
    echo "Aborted." >&2
    exit 0
  fi
fi

declare -a LOCAL_PATHS=()
while IFS= read -r lp || [[ -n "${lp:-}" ]]; do
  [[ -z "$lp" || "$lp" == "null" ]] && continue
  LOCAL_PATHS+=("$lp")
done < <(jq -r --arg r "$REPO" '[.[] | select(.repo_name == $r) | .local_path] | unique[]' "$files")

_n=${#LOCAL_PATHS[@]}
if filesync_progress_want "$_n"; then
  filesync_progress_begin "$_n"
fi
_pi=0
for lp in "${LOCAL_PATHS[@]}"; do
  filesync_remove_file_mapping_row "$PROJECT_ROOT" "$FILESYNC_FILES_FILE" "$lp" || filesync_die "remove-repo failed for one or more paths (see messages above)"
  _pi=$((_pi + 1))
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    filesync_progress_update "$_pi"
  fi
done

remove_repo_entry
filesync_progress_end
