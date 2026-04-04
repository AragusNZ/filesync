#!/usr/bin/env bash
# Remove a repo from global repos.json after removing all file mappings (all projects).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync remove repo <repo_name> [-y|--yes] [--force]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: rm -r

Remove a repo from global repos.json. Discovers file mappings like sync: every registered
checkout with .filesync/files.json plus the current project root.

  -y, --yes    Skip the confirmation prompt (after --force when mappings exist)
  --force      Required whenever any files.json row still references this repo (removes all mappings)

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/rm-mapping.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/filesync-projects.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/fs-lock.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'filesync_progress_end || true; filesync_global_lock_release 2>/dev/null || true; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

YES=0
FORCE=0
REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --yes)
      YES=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      if [[ -n "$REPO" ]]; then
        filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
        exit 1
      fi
      REPO="$1"
      shift
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

repos="$FILESYNC_REPOS_FILE"
files="$FILESYNC_FILES_FILE"

if ! jq -e --arg c "$REPO" 'any(.name == $c)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$REPO' not found in repos.${NC}" >&2
  exit 1
fi

repo_id="$(jq -r --arg c "$REPO" 'first(.[] | select(.name == $c) | .id) // empty' "$repos")"
rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"

declare -A _fp_seen=()
declare -a _TASK_ROOT=()
declare -a _TASK_FILES=()
declare -a _TASK_LP=()

_collect_tasks_for_files() {
  local proot="$1"
  local fp="$2"
  [[ -n "${_fp_seen[$fp]:-}" ]] && return 0
  _fp_seen[$fp]=1
  [[ -f "$fp" ]] || return 0
  local lp
  while IFS= read -r lp || [[ -n "${lp:-}" ]]; do
    [[ -z "$lp" || "$lp" == "null" ]] && continue
    _TASK_ROOT+=("$proot")
    _TASK_FILES+=("$fp")
    _TASK_LP+=("$lp")
  done < <(jq -r --arg id "$repo_id" --arg n "$REPO" '
    .[] | select(
      ($id != "" and $id != "null" and .repo_id == $id)
      or (
        $n != "" and .repo_name == $n
        and (($id == "" or $id == "null") or .repo_id == null or .repo_id == "")
      )
    ) | .local_path' "$fp")
}

while IFS= read -r proot || [[ -n "${proot:-}" ]]; do
  [[ -z "$proot" ]] && continue
  _collect_tasks_for_files "$proot" "$proot/.filesync/${FILESYNC_FILES_NAME}"
done < <(filesync_list_union_project_roots_for_global_ops "$PROJECT_ROOT" "$FILESYNC_SYSTEM_HOME" "$rroot" "$repos")

_collect_tasks_for_files "$PROJECT_ROOT" "$files"

total=${#_TASK_LP[@]}

if [[ "$total" -eq 0 ]]; then
  filesync_global_lock_acquire
  remove_repo_entry() {
    jq --arg n "$REPO" 'map(select(.name != $n))' "$repos" >"${repos}.tmp"
    mv "${repos}.tmp" "$repos"
    filesync_collections_prune_repo "$FILESYNC_COLLECTIONS_FILE" "$REPO" || filesync_die "could not update collections.json"
    echo -e "${GREEN}Removed repo:${NC} $REPO" >&2
  }
  remove_repo_entry
  filesync_global_lock_release
  filesync_progress_end
  exit 0
fi

if [[ "$total" -gt 0 ]] && [[ "$FORCE" -ne 1 ]]; then
  echo -e "${RED}filesync: repo '$REPO' has ${total} file mapping(s) across projects; pass --force to remove them all.${NC}" >&2
  echo "filesync: then use -y to skip the confirmation prompt." >&2
  exit 1
fi

echo -e "${YELLOW}Repo '$REPO' has ${total} file mapping(s) across all projects.${NC}" >&2
if [[ "$YES" -ne 1 ]]; then
  read -rp "Remove all mappings and drop this repo from the global store? [y/N] " ans || true
  if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
    echo "Aborted." >&2
    exit 0
  fi
fi

_n=$total
if filesync_progress_want "$_n"; then
  filesync_progress_begin "$_n"
fi
_pi=0

filesync_global_lock_acquire

for i in "${!_TASK_LP[@]}"; do
  filesync_remove_file_mapping_row "${_TASK_ROOT[$i]}" "${_TASK_FILES[$i]}" "${_TASK_LP[$i]}" || filesync_die "remove-repo failed for one or more paths (see messages above)"
  _pi=$((_pi + 1))
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    filesync_progress_update "$_pi"
  fi
done

jq --arg n "$REPO" 'map(select(.name != $n))' "$repos" >"${repos}.tmp"
mv "${repos}.tmp" "$repos"
filesync_collections_prune_repo "$FILESYNC_COLLECTIONS_FILE" "$REPO" || filesync_die "could not update collections.json"
echo -e "${GREEN}Removed repo:${NC} $REPO" >&2

filesync_global_lock_release
filesync_progress_end
