#!/usr/bin/env bash
# Show file mapping details and sibling clones for the same master; refresh status via check;
# optionally prompt to fix kind=master marker on the canonical master file.
# Dispatched as: filesync info [file|-f] <local-path> [--fix-marker]  (also: filesync i <path>)

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync info [file | -f] <local-path> [--fix-marker]
       filesync i <local-path> [--fix-marker]

Resolve a path to a tracked clone (row in this project's files.json) or to a file under a
registered repo checkout (master-at-checkout). Lists all mappings sharing the same master
(repo_file_path + repo identity), refreshes their status via filesync check --exact-local=…,
then prints a summary.

If the canonical master file's marker does not match whether any clones are tracked, you are
prompted to add or strip kind=master (TTY). Non-interactive: prints a hint; use --fix-marker
to perform the update without prompting.

See also: filesync info repo <name>; filesync info --help (file + repo).

Options:
  --fix-marker   Add or remove kind=master on the master file without a TTY prompt
EOF
  exit 0
fi

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/filesync-projects.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-banner.sh"

FIX_MARKER=false
LOCAL_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix-marker)
      FIX_MARKER=true
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync info [file | -f] <local-path> [--fix-marker]" >&2
      exit 1
      ;;
    *)
      if [[ -n "$LOCAL_ARG" ]]; then
        echo -e "${RED}Unexpected extra argument: $1${NC}" >&2
        echo "Usage: filesync info [file | -f] <local-path> [--fix-marker]" >&2
        exit 1
      fi
      LOCAL_ARG="$1"
      shift
      ;;
  esac
done

if [[ -z "$LOCAL_ARG" ]]; then
  echo -e "${RED}Missing <local-path>${NC}" >&2
  echo "Usage: filesync info [file | -f] <local-path> [--fix-marker]" >&2
  exit 1
fi

if [[ ! -e "$LOCAL_ARG" ]]; then
  echo -e "${RED}Not found: $LOCAL_ARG${NC}" >&2
  exit 1
fi
if [[ ! -f "$LOCAL_ARG" ]]; then
  echo -e "${RED}Not a regular file: $LOCAL_ARG${NC}" >&2
  exit 1
fi

ABS_TARGET="$(realpath "$LOCAL_ARG")"

# --- Find clone row in current project (local_path resolves to ABS_TARGET) ---
MATCH_LP=""
while IFS= read -r lp || [[ -n "${lp:-}" ]]; do
  [[ -z "$lp" || "$lp" == "null" ]] && continue
  # PROJECT_ROOT from filesync_command_init; distinct from PROJECT_ROOTS below
  # shellcheck disable=SC2153
  full_lp="$PROJECT_ROOT/$lp"
  [[ -f "$full_lp" ]] || continue
  if [[ "$(realpath "$full_lp")" == "$ABS_TARGET" ]]; then
    MATCH_LP="$lp"
    break
  fi
done < <(jq -r '.[] | .local_path // empty' "$FILESYNC_FILES_FILE")

MODE=""
RID=""
RNAME=""
RFP=""
if [[ -n "$MATCH_LP" ]]; then
  MODE="clone"
  RID=$(jq -r --arg lp "$MATCH_LP" '.[] | select(.local_path == $lp) | .repo_id // ""' "$FILESYNC_FILES_FILE" | head -1)
  RNAME=$(jq -r --arg lp "$MATCH_LP" '.[] | select(.local_path == $lp) | .repo_name // ""' "$FILESYNC_FILES_FILE" | head -1)
  RFP=$(jq -r --arg lp "$MATCH_LP" '.[] | select(.local_path == $lp) | .repo_file_path // ""' "$FILESYNC_FILES_FILE" | head -1)
else
  MODE="master-at-checkout"
  found=""
  while IFS= read -r rname && IFS= read -r rpath; do
    [[ -z "$rpath" || "$rpath" == "null" ]] && continue
    repo_dir="$(filesync_resolve_repo_checkout_dir "$REPO_PATH_ROOT" "$rpath")"
    [[ -z "$repo_dir" ]] && continue
    repo_dir="$(cd "$repo_dir" && pwd -P)"
    case "$ABS_TARGET" in
      "$repo_dir" | "$repo_dir"/*) ;;
      *) continue ;;
    esac
    rel="${ABS_TARGET#"$repo_dir"/}"
    if [[ -f "$ABS_TARGET" ]]; then
      RNAME="$rname"
      RFP="$rel"
      found=1
      break
    fi
  done < <(jq -r '.[] | (.name // ""), (.path // "")' "$FILESYNC_REPOS_FILE")
  if [[ -z "${found:-}" ]]; then
    echo -e "${RED}Path is not a tracked clone in this project and not under any resolvable repo checkout.${NC}" >&2
    exit 1
  fi
  RID=$(jq -r --arg n "$RNAME" 'first(.[] | select(.name == $n) | .id) // ""' "$FILESYNC_REPOS_FILE")
fi

if [[ -z "$RFP" || "$RFP" == "null" ]]; then
  echo -e "${RED}Could not determine repo_file_path for this file.${NC}" >&2
  exit 1
fi

# --- Collect related rows from union of project roots ---
mapfile -t PROJECT_ROOTS < <(filesync_list_union_project_roots_for_global_ops \
  "$PROJECT_ROOT" "$FILESYNC_SYSTEM_HOME" "$REPO_PATH_ROOT" "$FILESYNC_REPOS_FILE")

RELATED_LINES=()
declare -A ROOT_TO_LOCALS=()

for proot in "${PROJECT_ROOTS[@]}"; do
  [[ -z "$proot" ]] && continue
  fj="$proot/.filesync/$FILESYNC_FILES_NAME"
  [[ -f "$fj" ]] || continue
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "$line" ]] && continue
    RELATED_LINES+=("$proot	$line")
    lp="$(printf '%s' "$line" | jq -r '.local_path // ""')"
    if [[ -n "$lp" ]]; then
      if [[ -n "${ROOT_TO_LOCALS[$proot]:-}" ]]; then
        ROOT_TO_LOCALS[$proot]="${ROOT_TO_LOCALS[$proot]}"$'\n'"$lp"
      else
        ROOT_TO_LOCALS[$proot]="$lp"
      fi
    fi
  done < <(jq -c --arg rid "$RID" --arg rn "$RNAME" --arg rfp "$RFP" '
    .[]
    | select(.repo_file_path == $rfp)
    | select(
        (($rid != "") and ($rid != "null") and (.repo_id == $rid))
        or (
          (($rid == "") or ($rid == "null"))
          and (.repo_name == $rn)
        )
        or (
          ($rid != "") and ($rid != "null")
          and ((.repo_id == null) or (.repo_id == ""))
          and (.repo_name == $rn)
        )
      )
  ' "$fj" 2>/dev/null) || true
done

CLONE_COUNT=${#RELATED_LINES[@]}

# --- Refresh: run check --exact-local per project root ---
FS_BIN="$FILESYNC_PKG_ROOT/bin/filesync"
CHECK_RC=0
for proot in "${!ROOT_TO_LOCALS[@]}"; do
  [[ -z "${ROOT_TO_LOCALS[$proot]:-}" ]] && continue
  mapfile -t _locs <<<"${ROOT_TO_LOCALS[$proot]}"
  args=()
  for _loc in "${_locs[@]}"; do
    [[ -z "${_loc// }" ]] && continue
    args+=(--exact-local="$_loc")
  done
  [[ ${#args[@]} -eq 0 ]] && continue
  set +e
  (cd "$proot" && "$FS_BIN" check "${args[@]}")
  r=$?
  set -e
  if [[ "$r" -ne 0 ]]; then
    CHECK_RC="$r"
  fi
done

# --- Re-load related rows for display (after check updated json) ---
RELATED_LINES=()
for proot in "${PROJECT_ROOTS[@]}"; do
  [[ -z "$proot" ]] && continue
  fj="$proot/.filesync/$FILESYNC_FILES_NAME"
  [[ -f "$fj" ]] || continue
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "$line" ]] && continue
    RELATED_LINES+=("$proot	$line")
  done < <(jq -c --arg rid "$RID" --arg rn "$RNAME" --arg rfp "$RFP" '
    .[]
    | select(.repo_file_path == $rfp)
    | select(
        (($rid != "") and ($rid != "null") and (.repo_id == $rid))
        or (
          (($rid == "") or ($rid == "null"))
          and (.repo_name == $rn)
        )
        or (
          ($rid != "") and ($rid != "null")
          and ((.repo_id == null) or (.repo_id == ""))
          and (.repo_name == $rn)
        )
      )
  ' "$fj" 2>/dev/null) || true
done

CLONE_COUNT=${#RELATED_LINES[@]}

# --- Resolve canonical master path (for marker + warnings) ---
REPO_JSON_PATH="$(jq -r --arg n "$RNAME" '.[] | select(.name == $n) | .path // ""' "$FILESYNC_REPOS_FILE" | head -1)"
MASTER_ABS=""
if [[ -n "$REPO_JSON_PATH" && "$REPO_JSON_PATH" != "null" ]]; then
  _rd="$(filesync_resolve_repo_checkout_dir "$REPO_PATH_ROOT" "$REPO_JSON_PATH")"
  if [[ -n "$_rd" ]]; then
    _rd="$(cd "$_rd" && pwd -P)"
    MASTER_ABS="$_rd/$RFP"
  fi
fi

# --- Print report ---
echo "" >&2
filesync_print_section_title "filesync info file"
echo -e "${WHITE}Mode:${NC} $MODE" >&2
echo -e "${WHITE}Queried path:${NC} $ABS_TARGET" >&2
echo -e "${WHITE}Master:${NC} repo=$RNAME repo_file_path=$RFP repo_id=${RID:-}" >&2
if [[ "$MODE" == "clone" ]]; then
  echo -e "${GRAY}Current project row (local_path=$MATCH_LP):${NC}" >&2
  jq --arg lp "$MATCH_LP" '.[] | select(.local_path == $lp)' "$FILESYNC_FILES_FILE" >&2
fi
echo "" >&2
filesync_print_filter_note "Related mappings ($CLONE_COUNT row(s))"
for entry in "${RELATED_LINES[@]}"; do
  proot="${entry%%	*}"
  jrow="${entry#*	}"
  lp="$(printf '%s' "$jrow" | jq -r '.local_path // ""')"
  st="$(printf '%s' "$jrow" | jq -r '.sync_status // ""')"
  mw="$(printf '%s' "$jrow" | jq -r '(.check_marker_warnings // []) | join(",")')"
  mark=""
  if [[ "$(realpath "$proot/$lp" 2>/dev/null)" == "$ABS_TARGET" ]]; then
    mark=" (queried)"
  fi
  file_sync_print_file_row "$RNAME" "$RFP" "$lp" "$st" "$mw" >&2
  echo -e "  ${GRAY}project:${NC} $proot$mark" >&2
done

if [[ "$MODE" == "master-at-checkout" ]] && [[ -f "${MASTER_ABS:-}" ]] && ! has_master_file_sync_marker "$MASTER_ABS" 2>/dev/null; then
  echo "" >&2
  echo -e "${YELLOW}Warning: master file has no kind=master marker (see check marker codes).${NC}" >&2
fi

# --- Marker prompt / apply ---
MARKER_ACTION=""
if [[ -n "$MASTER_ABS" && -f "$MASTER_ABS" ]]; then
  if [[ "$CLONE_COUNT" -ge 1 ]]; then
    if ! has_master_file_sync_marker "$MASTER_ABS" 2>/dev/null; then
      if has_any_file_sync_marker "$MASTER_ABS" 2>/dev/null; then
        echo "" >&2
        echo -e "${YELLOW}Master file has a filesync marker that is not kind=master; cannot auto-add master marker.${NC}" >&2
      else
        MARKER_ACTION="add"
      fi
    fi
  else
    if has_master_file_sync_marker "$MASTER_ABS" 2>/dev/null; then
      MARKER_ACTION="strip"
    fi
  fi
fi

if [[ -n "$MARKER_ACTION" ]]; then
  echo "" >&2
  if [[ "$MARKER_ACTION" == "add" ]]; then
    msg="Add kind=master to: $MASTER_ABS"
  else
    msg="Remove filesync marker line(s) from (no tracked clones): $MASTER_ABS"
  fi
  do_apply=false
  if [[ "$FIX_MARKER" == true ]]; then
    do_apply=true
  elif [[ -t 0 ]]; then
    echo -e "${WHITE}$msg${NC}" >&2
    read -r -p "Apply? [y/N] " _ans || true
    if [[ "${_ans,,}" == "y" || "${_ans,,}" == "yes" ]]; then
      do_apply=true
    fi
  else
    echo -e "${GRAY}(stdin is not a TTY; skipping marker change. Re-run with --fix-marker or from a terminal.)${NC}" >&2
    echo -e "${WHITE}Would: $msg${NC}" >&2
  fi
  if [[ "$do_apply" == true ]]; then
    if [[ "$MARKER_ACTION" == "add" ]]; then
      if ! prepend_master_marker_to_file "$MASTER_ABS" "$RFP"; then
        echo -e "${RED}Failed to add kind=master marker.${NC}" >&2
        exit 1
      fi
      echo -e "${GREEN}Prepended kind=master to master file.${NC}" >&2
    else
      tmpm="$(mktemp)"
      strip_file_sync_marker_lines "$MASTER_ABS" "$tmpm"
      mv "$tmpm" "$MASTER_ABS"
      echo -e "${GREEN}Removed filesync marker line(s) from master file.${NC}" >&2
    fi
    echo -e "${GRAY}Consider: filesync check --exact-local=… in affected projects.${NC}" >&2
  fi
fi

if [[ "$CHECK_RC" -ne 0 ]]; then
  exit "$CHECK_RC"
fi
exit 0
