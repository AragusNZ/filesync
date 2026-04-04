#!/usr/bin/env bash
# Retarget all mappings for a canonical master after git mv (union across projects).
# Usage: retarget-master.sh <local_master|old_repo_path> <new_repo_file_path> [--move|--mv]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync retarget master <local_master|old_repo_path> <new_repo_file_path> [--move|--mv]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: retarget -m

Run this after you move or rename a master file in the upstream repo (e.g. git mv). filesync updates
every mapping that pointed at that master—across all projects that track it (same breadth as other
global master operations).

Arguments:

  <local_master|old_repo_path>
    If the old master file still exists on disk, give its path (anywhere under a registered checkout);
    resolution works like "filesync info file" on that path.
    If git mv already removed the old file, give the old path relative to the repo instead. filesync
    then finds the moved master using <new_repo_file_path> in your checkouts; if more than one
    checkout could match, run this from inside the checkout you mean.

  <new_repo_file_path>
    Where the master file lives in the repo after the move. That file must exist and carry a master
    marker (kind=master).

What happens next:

  Default (no --move): rows are marked master_file_moved. In each consumer project, run
    filesync sync --move
  to relocate local copies.

  --move / --mv: move each local tracked file to the new path in this command (fails if two rows in
  one project would end up at the same destination).

To retarget a single clone row in the current project only:
  filesync retarget clone …
EOF
  exit 0
fi

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/file-related-mappings.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/retarget-apply.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/paths.sh"

# shellcheck disable=SC2034
declare -A FILESYNC_REPO_DIR_CACHE
# shellcheck disable=SC2034
declare -a FILESYNC_CLONED_TEMP_DIRS

DO_MOVE=false
LOCAL_ARG=""
NEW_RFP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --move | --mv)
      DO_MOVE=true
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      if [[ -z "$LOCAL_ARG" ]]; then
        LOCAL_ARG="$1"
      elif [[ -z "$NEW_RFP" ]]; then
        NEW_RFP="$1"
      else
        filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$LOCAL_ARG" || -z "$NEW_RFP" ]]; then
  echo -e "${RED}Missing <local_master|old_repo_path> or <new_repo_file_path>${NC}" >&2
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

filesync_retarget_new_rfp_must_be_relative "$NEW_RFP" || exit 1

GATHER_PATH=""
if [[ -f "$LOCAL_ARG" ]]; then
  GATHER_PATH="$LOCAL_ARG"
else
  # First path missing: anchor gather from new master path in a unique registered checkout.
  declare -a _rt_repo_dirs=()
  while IFS= read -r rpath || [[ -n "${rpath:-}" ]]; do
    [[ -z "$rpath" || "$rpath" == "null" ]] && continue
    repo_dir="$(filesync_resolve_repo_checkout_dir "$REPO_PATH_ROOT" "$rpath")"
    [[ -z "$repo_dir" ]] && continue
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    full="$repo_dir/$NEW_RFP"
    [[ -f "$full" ]] || continue
    has_master_file_sync_marker "$full" 2>/dev/null || continue
    _rt_repo_dirs+=("$repo_dir")
  done < <(jq -r '.[].path // empty' "$FILESYNC_REPOS_FILE")

  mapfile -t _rt_uniq < <(printf '%s\n' "${_rt_repo_dirs[@]}" | sort -u)
  if [[ ${#_rt_uniq[@]} -eq 1 ]]; then
    GATHER_PATH="${_rt_uniq[0]}/$NEW_RFP"
  elif [[ ${#_rt_uniq[@]} -gt 1 ]]; then
    cwd="$(pwd -P)"
    declare -a _rt_inside=()
    for repo_dir in "${_rt_uniq[@]}"; do
      case "$cwd" in
        "$repo_dir" | "$repo_dir"/*) _rt_inside+=("$repo_dir") ;;
      esac
    done
    mapfile -t _rt_inside < <(printf '%s\n' "${_rt_inside[@]}" | sort -u)
    if [[ ${#_rt_inside[@]} -eq 1 ]]; then
      GATHER_PATH="${_rt_inside[0]}/$NEW_RFP"
    else
      echo -e "${RED}Ambiguous: <new_repo_file_path> exists as kind=master in multiple checkouts; use an existing master path as the first argument or run from inside one checkout.${NC}" >&2
      exit 1
    fi
  else
    echo -e "${RED}Not found: $LOCAL_ARG${NC}" >&2
    echo -e "${RED}Could not find kind=master at <new_repo_file_path> in any registered checkout.${NC}" >&2
    exit 1
  fi
fi

if ! filesync_file_rel_gather_from_path "$GATHER_PATH"; then
  exit 1
fi

if [[ "$FILESYNC_REL_MODE" != "master-at-checkout" ]]; then
  echo -e "${RED}This path is a tracked clone in the current project, not the canonical master in a checkout.${NC}" >&2
  echo -e "${YELLOW}To retarget a single clone row, use:${NC} filesync retarget clone <local_clone> <new_repo_file_path>${NC}" >&2
  exit 1
fi

# shellcheck disable=SC2153  # FILESYNC_REL_RFP set by filesync_file_rel_gather_from_path
if [[ "$FILESYNC_REL_RFP" != "$NEW_RFP" ]]; then
  echo -e "${RED}Gathered master repo_file_path ($FILESYNC_REL_RFP) does not match <new_repo_file_path> ($NEW_RFP).${NC}" >&2
  exit 1
fi

REPO_ROOT=""
if ! REPO_ROOT=$(filesync_get_repo_dir "$FILESYNC_REL_RNAME"); then
  echo -e "${RED}Could not resolve repo checkout for ${FILESYNC_REL_RNAME}${NC}" >&2
  exit 1
fi

FULL_NEW_MASTER="$REPO_ROOT/$NEW_RFP"
if [[ ! -f "$FULL_NEW_MASTER" ]]; then
  echo -e "${RED}New master not found in checkout: $NEW_RFP${NC}" >&2
  exit 1
fi
if ! has_master_file_sync_marker "$FULL_NEW_MASTER" 2>/dev/null; then
  echo -e "${RED}New path must be a kind=master file: $NEW_RFP${NC}" >&2
  exit 1
fi

NOW_ISO=$(file_sync_now_iso)

# --- Master-at-checkout: union of projects ---
OLD_RFP=""
if [[ ${#FILESYNC_RELATED_LINES[@]} -eq 0 ]]; then
  # shellcheck source=/dev/null
  source "$_CMD_ROOT/../lib/filesync-projects.sh"
  mapfile -t RETARGET_UNION_ROOTS < <(filesync_list_union_project_roots_for_global_ops "$PROJECT_ROOT" "$FILESYNC_SYSTEM_HOME" "$REPO_PATH_ROOT" "$FILESYNC_REPOS_FILE")
  declare -A _retarget_seen_old=()
  FILESYNC_RELATED_LINES=()
  for proot in "${RETARGET_UNION_ROOTS[@]}"; do
    fj="$proot/.filesync/$FILESYNC_FILES_NAME"
    [[ -f "$fj" ]] || continue
    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      rfp="$(printf '%s' "$row" | jq -r '.repo_file_path // ""')"
      [[ -n "$rfp" && "$rfp" != "$NEW_RFP" ]] || continue
      rid="$(printf '%s' "$row" | jq -r '.repo_id // ""')"
      repo_ok=false
      if [[ -n "$FILESYNC_REL_RID" && "$FILESYNC_REL_RID" != "null" && "$rid" == "$FILESYNC_REL_RID" ]]; then
        repo_ok=true
      fi
      [[ "$repo_ok" == true ]] || continue
      [[ ! -f "$REPO_ROOT/$rfp" ]] || continue
      FILESYNC_RELATED_LINES+=("$proot	$row")
      _retarget_seen_old[$rfp]=1
    done < <(jq -c '.[]' "$fj")
  done
  mapfile -t _retarget_old_keys < <(printf '%s\n' "${!_retarget_seen_old[@]}" | sort -u)
  if [[ ${#_retarget_old_keys[@]} -ne 1 ]]; then
    echo -e "${RED}Could not infer the old master path (${#_retarget_old_keys[@]} distinct missing repo_file_path value(s) for this repo). Use a tracked clone with retarget clone or run check.${NC}" >&2
    exit 1
  fi
  OLD_RFP="${_retarget_old_keys[0]}"
else
  OLD_RFP="$FILESYNC_REL_RFP"
fi

if [[ ${#FILESYNC_RELATED_LINES[@]} -eq 0 ]]; then
  echo -e "${RED}No file mappings matched this master.${NC}" >&2
  exit 1
fi

if [[ "$OLD_RFP" == "$NEW_RFP" ]]; then
  echo -e "${YELLOW}repo_file_path already equals $NEW_RFP; nothing to do.${NC}" >&2
  exit 0
fi

declare -A PROOT_COUNT=()
for line in "${FILESYNC_RELATED_LINES[@]}"; do
  [[ -z "$line" ]] && continue
  proot="${line%%	*}"
  row_json="${line#*	}"
  [[ -z "$proot" ]] && continue
  lp_row="$(printf '%s' "$row_json" | jq -r '.local_path // ""')"
  [[ -n "$lp_row" ]] || continue
  key="$proot"
  PROOT_COUNT[$key]=$((${PROOT_COUNT[$key]:-0} + 1))
done

if [[ "$DO_MOVE" == true ]]; then
  for proot in "${!PROOT_COUNT[@]}"; do
    c="${PROOT_COUNT[$proot]}"
    if [[ "$c" -gt 1 ]]; then
      echo -e "${RED}retarget master --move: project $proot has $c mappings for this master; move would collide. Omit --move or fix mappings.${NC}" >&2
      exit 1
    fi
  done
fi

declare -A RETARGET_SEEN_PROOT=()
for line in "${FILESYNC_RELATED_LINES[@]}"; do
  [[ -z "$line" ]] && continue
  proot="${line%%	*}"
  [[ -z "$proot" ]] && continue
  [[ -n "${RETARGET_SEEN_PROOT[$proot]:-}" ]] && continue
  RETARGET_SEEN_PROOT[$proot]=1

  fj="$proot/.filesync/$FILESYNC_FILES_NAME"
  [[ -f "$fj" ]] || continue

  if [[ "$DO_MOVE" == true ]]; then
    lp_row="$(jq -r --arg oldrfp "$OLD_RFP" --arg rid "$FILESYNC_REL_RID" '
      [.[] | select(.repo_file_path == $oldrfp) | select(($rid != "") and ($rid != "null") and (.repo_id == $rid))]
      | .[0].local_path // empty
    ' "$fj")"
    [[ -n "$lp_row" ]] || continue
    if [[ "$lp_row" != "$NEW_RFP" ]]; then
      src="$proot/$lp_row"
      dst="$proot/$NEW_RFP"
      [[ -f "$src" ]] || {
        echo -e "${RED}Local file missing in $proot: $lp_row${NC}" >&2
        exit 1
      }
      if [[ -e "$dst" ]]; then
        if [[ "$(filesync_canonical_existing "$src" 2>/dev/null)" != "$(filesync_canonical_existing "$dst" 2>/dev/null)" ]]; then
          echo -e "${RED}Destination already exists: $proot/$NEW_RFP${NC}" >&2
          exit 1
        fi
      fi
      mkdir -p "$(dirname "$dst")"
      mv "$src" "$dst"
    fi
  fi
  filesync_retarget_apply_jq_master_union "$fj" "$OLD_RFP" "$NEW_RFP" "$FILESYNC_REL_RID" "$DO_MOVE" "$NOW_ISO"
done

echo -e "${GREEN}Retargeted master:${NC} $OLD_RFP -> $NEW_RFP (${#FILESYNC_RELATED_LINES[@]} row(s) across projects)" >&2
if [[ "$DO_MOVE" != true ]]; then
  echo -e "${YELLOW}Local paths unchanged; run ${WHITE}filesync sync --move${YELLOW} to move clones to match the new path.${NC}" >&2
fi
