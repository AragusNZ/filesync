#!/usr/bin/env bash
# Retarget repo_file_path after the master file moved in the repo; optionally move local clones.
# Usage: retarget.sh <local_file|old_path> <new_repo_file_path> [--move|--mv]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync retarget <local_file|old_path> <new_repo_file_path> [--move|--mv]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}

Update repo_file_path after the master moved in the repo (same path convention as in files.json).
The first argument <local_file|old_path> must be an existing file, resolved the same way as
"filesync info file" (often your clone still at the old local_path, or the master path in the checkout):

  • Tracked clone (path under the current project): affects only this project's row.
  • Master file (path inside a registered repo checkout): affects every mapping for that
    master across all projects in the same union as "info file" / "remove repo".

Behavior differs by which kind of path you pass:

  Clone mode — updates repo_file_path to <new_repo_file_path> for the single matching row.
    Without --move/--mv: sets sync_status sync_required (local file stays at local_path).
    With --move/--mv: mv local file to <new_repo_file_path> (project-relative) and set local_path.

  Master mode — updates repo_file_path for every sibling row (all consumer projects).
    Without --move/--mv: sets sync_status master_file_moved (clone files stay put until
      "filesync sync --move").
    With --move/--mv: mv each local clone to <new_repo_file_path> and set local_path;
      rejected if more than one mapping for this master exists in the same project (--move
      would overwrite the same destination).

<new_repo_file_path> must already exist in the checkout with kind=master (e.g. after git mv).
If files.json still lists the old path and "info" would find no siblings, retarget can infer
the old path from rows whose master file is missing; otherwise pass a clone path as
<local_file|old_path>.
EOF
  exit 0
fi

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/file-related-mappings.sh"

# shellcheck disable=SC2034  # required by filesync_get_repo_dir (repo-resolve.sh)
declare -A FILESYNC_REPO_DIR_CACHE
# shellcheck disable=SC2034  # required by filesync_get_repo_dir (repo-resolve.sh)
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
  echo -e "${RED}Missing <local_file|old_path> or <new_repo_file_path>${NC}" >&2
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

case "$NEW_RFP" in
  /* | ../* | */../* | .. | */..)
    echo -e "${RED}<new_repo_file_path> must be repo-relative (no leading / or .. segments).${NC}" >&2
    exit 1
    ;;
esac

if ! filesync_file_rel_gather_from_path "$LOCAL_ARG"; then
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

retarget_apply_jq_clone() {
  local fj="$1"
  local lp="$2"
  if [[ "$DO_MOVE" == true ]]; then
    jq --arg lp "$lp" --arg nrp "$NEW_RFP" --arg now "$NOW_ISO" \
      'map(if .local_path == $lp then . + {repo_file_path: $nrp, local_path: $nrp, sync_status: "sync_required", last_check_at: $now} else . end)' "$fj" >"${fj}.tmp"
  else
    jq --arg lp "$lp" --arg nrp "$NEW_RFP" --arg now "$NOW_ISO" \
      'map(if .local_path == $lp then . + {repo_file_path: $nrp, sync_status: "sync_required", last_check_at: $now} else . end)' "$fj" >"${fj}.tmp"
  fi
  mv "${fj}.tmp" "$fj"
}

retarget_apply_jq_master_union() {
  local fj="$1"
  if [[ "$DO_MOVE" == true ]]; then
    jq --arg oldrfp "$OLD_RFP" --arg nrp "$NEW_RFP" --arg rid "$FILESYNC_REL_RID" --arg rn "$FILESYNC_REL_RNAME" --arg now "$NOW_ISO" \
      'map(
        if (.repo_file_path == $oldrfp) and (
            (($rid != "") and ($rid != "null") and (.repo_id == $rid))
            or ((($rid == "") or ($rid == "null")) and (.repo_name == $rn))
            or (($rid != "") and ($rid != "null") and ((.repo_id == null) or (.repo_id == "")) and (.repo_name == $rn))
          )
        then . + {repo_file_path: $nrp, local_path: $nrp, sync_status: "sync_required", last_check_at: $now}
        else . end
      )' "$fj" >"${fj}.tmp"
  else
    jq --arg oldrfp "$OLD_RFP" --arg nrp "$NEW_RFP" --arg rid "$FILESYNC_REL_RID" --arg rn "$FILESYNC_REL_RNAME" --arg now "$NOW_ISO" \
      'map(
        if (.repo_file_path == $oldrfp) and (
            (($rid != "") and ($rid != "null") and (.repo_id == $rid))
            or ((($rid == "") or ($rid == "null")) and (.repo_name == $rn))
            or (($rid != "") and ($rid != "null") and ((.repo_id == null) or (.repo_id == "")) and (.repo_name == $rn))
          )
        then . + {repo_file_path: $nrp, sync_status: "master_file_moved", last_check_at: $now}
        else . end
      )' "$fj" >"${fj}.tmp"
  fi
  mv "${fj}.tmp" "$fj"
}

if [[ "$FILESYNC_REL_MODE" == "clone" ]]; then
  # shellcheck disable=SC2153  # FILESYNC_REL_RFP set by filesync_file_rel_gather_from_path (clone branch)
  if [[ "$FILESYNC_REL_RFP" == "$NEW_RFP" ]]; then
    echo -e "${YELLOW}repo_file_path already equals $NEW_RFP; nothing to do.${NC}" >&2
    exit 0
  fi
  lp="${FILESYNC_REL_MATCH_LP:?}"
  fj="$FILESYNC_FILES_FILE"
  if [[ "$DO_MOVE" == true ]]; then
    src="$PROJECT_ROOT/$lp"
    dst="$PROJECT_ROOT/$NEW_RFP"
    if [[ "$lp" != "$NEW_RFP" ]]; then
      [[ -f "$src" ]] || {
        echo -e "${RED}Local file missing: $lp${NC}" >&2
        exit 1
      }
      if [[ -e "$dst" ]]; then
        if [[ "$(filesync_canonical_existing "$src" 2>/dev/null)" == "$(filesync_canonical_existing "$dst" 2>/dev/null)" ]]; then
          :
        else
          echo -e "${RED}Destination already exists: $NEW_RFP${NC}" >&2
          exit 1
        fi
      fi
      mkdir -p "$(dirname "$dst")"
      mv "$src" "$dst"
    fi
  fi
  retarget_apply_jq_clone "$fj" "$lp"
  echo -e "${GREEN}Retargeted clone:${NC} repo_file_path ${FILESYNC_REL_RFP} -> $NEW_RFP (project $PROJECT_ROOT)" >&2
  exit 0
fi

# --- Master-at-checkout: union of projects ---
OLD_RFP=""
if [[ ${#FILESYNC_RELATED_LINES[@]} -eq 0 ]]; then
  # files.json may still list the old repo_file_path while the master already lives at NEW_RFP.
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
      rname="$(printf '%s' "$row" | jq -r '.repo_name // ""')"
      repo_ok=false
      if [[ -n "$FILESYNC_REL_RID" && "$FILESYNC_REL_RID" != "null" ]]; then
        [[ "$rid" == "$FILESYNC_REL_RID" ]] && repo_ok=true
      elif [[ -n "$rname" ]]; then
        [[ "$rname" == "$FILESYNC_REL_RNAME" ]] && repo_ok=true
      fi
      [[ "$repo_ok" == true ]] || continue
      [[ ! -f "$REPO_ROOT/$rfp" ]] || continue
      FILESYNC_RELATED_LINES+=("$proot	$row")
      _retarget_seen_old[$rfp]=1
    done < <(jq -c '.[]' "$fj")
  done
  mapfile -t _retarget_old_keys < <(printf '%s\n' "${!_retarget_seen_old[@]}" | sort -u)
  if [[ ${#_retarget_old_keys[@]} -ne 1 ]]; then
    echo -e "${RED}Could not infer the old master path (${#_retarget_old_keys[@]} distinct missing repo_file_path value(s) for this repo). Use a tracked clone as <local_file|old_path> or run check.${NC}" >&2
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
      echo -e "${RED}retarget --move: project $proot has $c mappings for this master; move would collide. Omit --move or fix mappings.${NC}" >&2
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
    lp_row="$(jq -r --arg oldrfp "$OLD_RFP" --arg rid "$FILESYNC_REL_RID" --arg rn "$FILESYNC_REL_RNAME" '
      [.[] | select(.repo_file_path == $oldrfp) | select(
        (($rid != "") and ($rid != "null") and (.repo_id == $rid))
        or ((($rid == "") or ($rid == "null")) and (.repo_name == $rn))
        or (($rid != "") and ($rid != "null") and ((.repo_id == null) or (.repo_id == "")) and (.repo_name == $rn))
      )] | .[0].local_path // empty
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
  retarget_apply_jq_master_union "$fj"
done

echo -e "${GREEN}Retargeted master:${NC} $OLD_RFP -> $NEW_RFP (${#FILESYNC_RELATED_LINES[@]} row(s) across projects)" >&2
if [[ "$DO_MOVE" != true ]]; then
  echo -e "${YELLOW}Local paths unchanged; run ${WHITE}filesync sync --move${YELLOW} to move clones to match the new path.${NC}" >&2
fi
exit 0
