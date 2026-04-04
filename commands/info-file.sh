#!/usr/bin/env bash
# Show file mapping details and sibling clones for the same master; refresh status via check;
# optionally prompt to fix kind=master marker on the canonical master file.
# Dispatched as: filesync info [file|-f] <local-path> [--fix-marker]  (also: filesync i <path>)

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync info [file | -f] <local-path> [--fix-marker]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
       filesync i <local-path> [--fix-marker]

Resolve a path to a tracked clone (row in this project's files.json) or to the canonical
master file under a registered repo checkout. Lists all mappings sharing the same master
(repo_file_path + repo identity), refreshes their status via filesync check --exact-local=…,
then prints a summary on stderr (Role: clone or Role: master, master key, related rows).

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
source "$_CMD_ROOT/../lib/file-related-mappings.sh"
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
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      if [[ -n "$LOCAL_ARG" ]]; then
        filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
        exit 1
      fi
      LOCAL_ARG="$1"
      shift
      ;;
  esac
done

if [[ -z "$LOCAL_ARG" ]]; then
  echo -e "${RED}Missing <local-path>${NC}" >&2
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

if ! filesync_file_rel_gather_from_path "$LOCAL_ARG"; then
  exit 1
fi

CLONE_COUNT=${#FILESYNC_RELATED_LINES[@]}

# --- Refresh: run check --exact-local per project root ---
FS_BIN="$FILESYNC_PKG_ROOT/bin/filesync"
CHECK_RC=0
for proot in "${!FILESYNC_REL_ROOT_TO_LOCALS[@]}"; do
  [[ -z "${FILESYNC_REL_ROOT_TO_LOCALS[$proot]:-}" ]] && continue
  mapfile -t _locs <<<"${FILESYNC_REL_ROOT_TO_LOCALS[$proot]}"
  args=()
  for _loc in "${_locs[@]}"; do
    [[ -z "${_loc// }" ]] && continue
    args+=(--exact-local="$_loc")
  done
  [[ ${#args[@]} -eq 0 ]] && continue
  set +e
  (cd "$proot" && env -u FILESYNC_DIR -u FILESYNC_PROJECT_ROOT -u CONFIG_FILE -u FILESYNC_STATE_FILE -u PROJECT_ROOT \
    "$FS_BIN" check "${args[@]}")
  r=$?
  set -e
  if [[ "$r" -ne 0 ]]; then
    CHECK_RC="$r"
  fi
done

filesync_file_rel_reload_related_lines
CLONE_COUNT=${#FILESYNC_RELATED_LINES[@]}

# --- Resolve canonical master path (for marker + warnings) ---
REPO_JSON_PATH="$(jq -r --arg n "$FILESYNC_REL_RNAME" '.[] | select(.name == $n) | .path // ""' "$FILESYNC_REPOS_FILE" | head -1)"
MASTER_ABS=""
if [[ -n "$REPO_JSON_PATH" && "$REPO_JSON_PATH" != "null" ]]; then
  _rd="$(filesync_resolve_repo_checkout_dir "$REPO_PATH_ROOT" "$REPO_JSON_PATH")"
  if [[ -n "$_rd" ]]; then
    _rd="$(cd "$_rd" && pwd -P)"
    MASTER_ABS="$_rd/$FILESYNC_REL_RFP"
  fi
fi

# --- Print report ---
echo "" >&2
filesync_print_info_heading "Summary"
if [[ "$FILESYNC_REL_MODE" == "clone" ]]; then
  filesync_print_info_kv "Role" "clone"
else
  filesync_print_info_kv "Role" "master"
fi
filesync_print_info_kv "Queried path" "$FILESYNC_REL_ABS_TARGET"
filesync_print_info_kv "Repo" "$FILESYNC_REL_RNAME"
filesync_print_info_kv "Repo file path" "$FILESYNC_REL_RFP"
_rid="${FILESYNC_REL_RID:-}"
[[ -z "$_rid" ]] && _rid="—"
filesync_print_info_kv "Repo id" "$_rid"
if [[ "$FILESYNC_REL_MODE" == "master-at-checkout" ]]; then
  echo -e "  ${GRAY}Clones below: each line is a tracked row (same repo + repo_file_path) across projects.${NC}" >&2
fi
if [[ "$FILESYNC_REL_MODE" == "clone" ]]; then
  echo "" >&2
  echo -e "  ${GRAY}Current project row (local_path=$FILESYNC_REL_MATCH_LP):${NC}" >&2
  _row_json="$(jq -c --arg lp "$FILESYNC_REL_MATCH_LP" '.[] | select(.local_path == $lp)' "$FILESYNC_FILES_FILE" | head -1)"
  if [[ -n "$_row_json" ]]; then
    echo "$_row_json" | jq . | sed 's/^/  /' >&2
  fi
fi
echo "" >&2
filesync_print_info_heading "Related mappings ($CLONE_COUNT)"
_rel_first=true
for entry in "${FILESYNC_RELATED_LINES[@]}"; do
  if [[ "$_rel_first" == true ]]; then
    _rel_first=false
  else
    echo "" >&2
  fi
  proot="${entry%%	*}"
  jrow="${entry#*	}"
  lp="$(printf '%s' "$jrow" | jq -r '.local_path // ""')"
  st="$(printf '%s' "$jrow" | jq -r '.sync_status // ""')"
  mw="$(printf '%s' "$jrow" | jq -r '(.check_marker_warnings // []) | join(",")')"
  mark=""
  if [[ "$(filesync_canonical_existing "$proot/$lp" 2>/dev/null)" == "$FILESYNC_REL_ABS_TARGET" ]]; then
    mark=" (queried)"
  fi
  printf '  ' >&2
  file_sync_print_file_row "$FILESYNC_REL_RNAME" "$FILESYNC_REL_RFP" "$lp" "$st" "$mw" >&2
  echo -e "    ${GRAY}project:${NC} $proot$mark" >&2
done

if [[ "$FILESYNC_REL_MODE" == "master-at-checkout" ]] && [[ -f "${MASTER_ABS:-}" ]] && ! has_master_file_sync_marker "$MASTER_ABS" 2>/dev/null; then
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
      if ! prepend_master_marker_to_file "$MASTER_ABS" "$FILESYNC_REL_RFP"; then
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
