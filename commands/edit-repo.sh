#!/usr/bin/env bash
# CLI: filesync edit-repo — update global repos.json; rename updates display name (stable repo id) and all projects' files.json + markers.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync edit-repo <repo_name> [options]
Alias: er

Update a repo entry in the global store (repos.json). At least one of the options below is required.

Options:
  --rename=new_name    Rename repo (updates repo_name in every project's files.json and repo= in markers).
                       Refused when mappings exist and the repo has check_sync_enabled false, or when a
                       host checkout has mirror_in_enabled false (see man filesync).
  --path=new_path      Set checkout path
  --url=new_url        Set remote URL
  --branch=name        Change branch

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/filesync-projects.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/repo-flags.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/fs-lock.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

REPO_CURRENT=""
RENAME=""
PATH_NEW=""
URL_NEW=""
BRANCH_NEW=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rename=*)
      RENAME="${1#*=}"
      shift
      ;;
    --path=*)
      PATH_NEW="${1#*=}"
      shift
      ;;
    --url=*)
      URL_NEW="${1#*=}"
      shift
      ;;
    --branch=*)
      BRANCH_NEW="${1#*=}"
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync edit-repo <repo_name> [--rename=new] [--path=...] [--url=...] [--branch=...]" >&2
      exit 1
      ;;
    *)
      if [[ -z "$REPO_CURRENT" ]]; then
        REPO_CURRENT="$1"
      else
        echo -e "${RED}Unexpected argument: $1${NC}" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$REPO_CURRENT" ]]; then
  echo -e "${RED}Usage: filesync edit-repo <repo_name> [--rename=new] [--path=...] [--url=...] [--branch=...]${NC}" >&2
  echo "At least one of --rename, --path, --url, or --branch is required." >&2
  exit 1
fi

if [[ -z "$RENAME" ]] && [[ -z "$PATH_NEW" ]] && [[ -z "$URL_NEW" ]] && [[ -z "$BRANCH_NEW" ]]; then
  echo -e "${RED}Error: specify at least one of --rename, --path, --url, --branch${NC}" >&2
  exit 1
fi

repos="$FILESYNC_REPOS_FILE"

if ! jq -e --arg c "$REPO_CURRENT" 'any(.name == $c)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$REPO_CURRENT' not found in repos.${NC}" >&2
  exit 1
fi

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  if jq -e --arg n "$RENAME" 'any(.name == $n)' "$repos" &>/dev/null; then
    echo -e "${RED}Error: Repo name '$RENAME' already exists.${NC}" >&2
    exit 1
  fi
  if [[ -f "$FILESYNC_COLLECTIONS_FILE" ]] && filesync_collections_name_taken "$FILESYNC_COLLECTIONS_FILE" "$RENAME"; then
    echo -e "${RED}Error: '$RENAME' is already a collection name.${NC}" >&2
    exit 1
  fi
fi

repo_id="$(jq -r --arg c "$REPO_CURRENT" 'first(.[] | select(.name == $c) | .id) // empty' "$repos")"

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  rroot_pre="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"
  _any_rows=0
  while IFS= read -r proot || [[ -n "${proot:-}" ]]; do
    [[ -z "$proot" ]] && continue
    fp="$proot/.filesync/${FILESYNC_FILES_NAME}"
    cnt="$(filesync_count_files_json_rows_for_repo "$fp" "$repo_id" "$REPO_CURRENT")"
    [[ "${cnt:-0}" -eq 0 ]] && continue
    _any_rows=1
    host="$(filesync_repo_name_for_checkout_dir "$proot" "$rroot_pre" "$repos" || true)"
    if [[ -n "${host:-}" ]] && ! filesync_repo_mirror_in_enabled "$repos" "$host"; then
      echo -e "${RED}Error: cannot rename '$REPO_CURRENT': file mappings live under checkout of repo '$host', which has mirror_in_enabled false.${NC}" >&2
      echo "filesync: enable mirror-in for that repo or remove the mappings before renaming." >&2
      exit 1
    fi
  done < <(filesync_list_union_project_roots_for_global_ops "$PROJECT_ROOT" "$FILESYNC_SYSTEM_HOME" "$rroot_pre" "$repos")
  if [[ "$_any_rows" -eq 1 ]] && ! filesync_repo_check_sync_enabled "$repos" "$REPO_CURRENT"; then
    echo -e "${RED}Error: cannot rename '$REPO_CURRENT' while check_sync_enabled is false (file mappings still reference it).${NC}" >&2
    echo "filesync: enable the repo first (e.g. filesync enable '$REPO_CURRENT')." >&2
    exit 1
  fi
fi

tmp_repos="$(mktemp)"
cleanup_er() {
  # shellcheck disable=SC2317
  rm -f "$tmp_repos"
}
trap 'cleanup_er; filesync_global_lock_release 2>/dev/null || true; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

jq --arg c "$REPO_CURRENT" \
  --arg newname "$RENAME" \
  --arg p "$PATH_NEW" \
  --arg u "$URL_NEW" \
  --arg b "$BRANCH_NEW" \
  'map(
    if .name == $c then
      .name = (if $newname != "" then $newname else .name end)
      | .path = (if $p != "" then $p else .path end)
      | .url = (if $u != "" then $u else .url end)
      | .branch = (if $b != "" then $b else .branch end)
    else . end
  )' "$repos" >"$tmp_repos"

filesync_global_lock_acquire

mv "$tmp_repos" "$repos"

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"
  while IFS= read -r proot || [[ -n "${proot:-}" ]]; do
    [[ -z "$proot" ]] && continue
    fp="$proot/.filesync/${FILESYNC_FILES_NAME}"
    [[ -f "$fp" ]] || continue
    tmp_f="$(mktemp)"
    jq --arg id "$repo_id" --arg oldn "$REPO_CURRENT" --arg newn "$RENAME" \
      'map(
        if ($id != "" and $id != "null" and .repo_id == $id)
           or (
             .repo_name == $oldn
             and (($id == "" or $id == "null") or .repo_id == null or .repo_id == "")
           )
        then .repo_name = $newn else . end
      )' \
      "$fp" >"$tmp_f"
    mv "$tmp_f" "$fp"
    while IFS= read -r _lp || [[ -n "${_lp:-}" ]]; do
      [[ -z "$_lp" || "$_lp" == "null" ]] && continue
      _full="${proot}/${_lp}"
      filesync_marker_rename_repo_in_file "$_full" "$REPO_CURRENT" "$RENAME" || true
    done < <(jq -r --arg id "$repo_id" --arg o "$REPO_CURRENT" \
      '.[] | select(
        ($id != "" and $id != "null" and .repo_id == $id)
        or (
          $o != "" and .repo_name == $o
          and (($id == "" or $id == "null") or .repo_id == null or .repo_id == "")
        )
      ) | .local_path' "$fp")
  done < <(filesync_list_union_project_roots_for_global_ops "$PROJECT_ROOT" "$FILESYNC_SYSTEM_HOME" "$rroot" "$repos")
fi

filesync_global_lock_release
trap 'cleanup_er; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

echo -e "${GREEN}Updated repo${NC} ${WHITE}$REPO_CURRENT${NC}:" >&2
if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  echo "  Renamed to: $RENAME (all projects' files.json and clone/detached markers)" >&2
fi
if [[ -n "$PATH_NEW" ]]; then echo "  path: $PATH_NEW" >&2; fi
if [[ -n "$URL_NEW" ]]; then echo "  url: $URL_NEW" >&2; fi
if [[ -n "$BRANCH_NEW" ]]; then echo "  branch: $BRANCH_NEW" >&2; fi
exit 0
