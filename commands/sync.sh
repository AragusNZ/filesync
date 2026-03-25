#!/usr/bin/env bash
# Sync from master repos into project (updates .filesync/files.json rows).
# Usage: sync.sh [--repo=name] [--file=path_fragment] [--dry-run] [--force] [--showall] [--status=a,b,...] [--include-detached]
# Path fragment: substring match on local_path or repo_file_path (after optional --repo filter).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-banner.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"

REPO_FILTER=""
FILE_FRAGMENT=""
DRY_RUN=false
FORCE=false
STATUS_CSV=""
INCLUDE_DETACHED=false
SHOWALL=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --showall) SHOWALL=true; shift ;;
    --include-detached) INCLUDE_DETACHED=true; shift ;;
    --status=*) STATUS_CSV="${1#*=}"; shift ;;
    --repo=*)
      REPO_FILTER="${1#*=}"
      shift
      ;;
    --file=*)
      FILE_FRAGMENT="${1#*=}"
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      exit 1
      ;;
    *)
      echo -e "${RED}Unexpected argument: $1${NC}" >&2
      exit 1
      ;;
  esac
done

sync_entry_allowed() {
  local status="${1:-}"
  [[ "$status" == "null" ]] && status=""
  if [[ -z "$STATUS_CSV" ]]; then
    if [[ "$status" == "detached" ]]; then
      [[ "$INCLUDE_DETACHED" == true ]] && return 0
      return 1
    fi
    # Missing local files should be pulled from master by default.
    if [[ "$status" == "error_missing_local" ]]; then
      return 0
    fi
    # --force: pull from master even when check reported local_newer / conflict.
    if [[ "$FORCE" == true ]]; then
      [[ "$status" == "local_newer" || "$status" == "conflict" ]] && return 0
    fi
    [[ -z "$status" ]] || [[ "$status" == "sync_required" ]] && return 0
    return 1
  fi
  file_sync_status_matches_csv "$status" "$STATUS_CSV" "$INCLUDE_DETACHED"
}

# shellcheck disable=SC2034
declare -A FILESYNC_REPO_DIR_CACHE
declare -a FILESYNC_CLONED_TEMP_DIRS
SYNC_ROWS_TSV=""

cleanup_sync_exit() {
  # shellcheck disable=SC2317
  filesync_progress_end || true
  # shellcheck disable=SC2317
  rm -f "${FILESYNC_STATE_FILE:-}" "${SYNC_ROWS_TSV:-}"
  # shellcheck disable=SC2317
  rm -rf "${FILESYNC_CLONED_TEMP_DIRS[@]:-}"
}
trap cleanup_sync_exit EXIT

if ! jq -e '.file_sync_enabled == true' "$CONFIG_FILE" &>/dev/null; then
  filesync_print_disabled_hint
  exit 0
fi

if ! jq -e '.repos | length > 0' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo -e "${RED}Error: Config must have at least one entry in repos${NC}" >&2
  exit 1
fi

SYNCED=0
ALREADY_SYNCED=0
FAILED=0
SKIPPED=0
STATUS_SKIPPED=0

FILE_PATH_MATCHES=0

filesync_print_sync_banner
filesync_print_filter_context "$REPO_FILTER" "$FILE_FRAGMENT" "$STATUS_CSV" "$INCLUDE_DETACHED" 1 "$FORCE"
filesync_print_sync_showall_banner "$SHOWALL"
echo "" >&2

SYNC_ROWS_TSV=$(mktemp)
filesync_config_file_rows_tsv_to "$SYNC_ROWS_TSV" "$CONFIG_FILE" "$REPO_FILTER" "$FILE_FRAGMENT"
FILES_WORK_COUNT=$(wc -l < "$SYNC_ROWS_TSV")
FILES_WORK_COUNT="${FILES_WORK_COUNT//[[:space:]]/}"

if filesync_progress_want "$FILES_WORK_COUNT"; then
  filesync_progress_begin "$FILES_WORK_COUNT"
fi

SYNC_ROW_PROGRESS=0
filesync_sync_iter_progress() {
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    SYNC_ROW_PROGRESS=$((SYNC_ROW_PROGRESS + 1))
    filesync_progress_update "$SYNC_ROW_PROGRESS"
  fi
}

while IFS=$'\t' read -r i REPO_NAME LOCAL_PATH REPO_FILE_PATH ROW_STATUS _last_sync_unused; do
  if [[ -z "$REPO_NAME" ]] || [[ "$REPO_NAME" == "null" ]]; then
    filesync_print_config_error_invalid_repo_name "$i"
    FAILED=$((FAILED + 1))
    filesync_sync_iter_progress
    continue
  fi

  FILE_PATH_MATCHES=$((FILE_PATH_MATCHES + 1))

  if [[ -z "$LOCAL_PATH" ]] || [[ "$LOCAL_PATH" == "null" ]]; then
    filesync_print_config_error_invalid_local_path "$i"
    FAILED=$((FAILED + 1))
    filesync_sync_iter_progress
    continue
  fi

  if [[ -z "$REPO_FILE_PATH" ]] || [[ "$REPO_FILE_PATH" == "null" ]]; then
    filesync_print_config_error_invalid_repo_file_path "$LOCAL_PATH"
    FAILED=$((FAILED + 1))
    filesync_sync_iter_progress
    continue
  fi

  if ! sync_entry_allowed "$ROW_STATUS"; then
    file_sync_print_sync_skip_line "⊘" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH" "not selected; status=${ROW_STATUS:-unset}"
    # Rows previously checked as synced are still "already in sync" even if
    # excluded by the current status selection.
    if [[ "${ROW_STATUS:-}" == "synced" ]]; then
      ALREADY_SYNCED=$((ALREADY_SYNCED + 1))
    fi
    STATUS_SKIPPED=$((STATUS_SKIPPED + 1))
    filesync_sync_iter_progress
    continue
  fi

  REPO_ROOT=""
  REPO_ROOT=$(filesync_get_repo_dir "$REPO_NAME") || { FAILED=$((FAILED + 1)); filesync_sync_iter_progress; continue; }

  FULL_LOCAL_PATH="$PROJECT_ROOT/$LOCAL_PATH"
  FULL_MASTER_PATH="$REPO_ROOT/$REPO_FILE_PATH"

  if [[ ! -f "$FULL_MASTER_PATH" ]]; then
    file_sync_print_sync_action_line "${RED}✗${NC}" "${RED}" "source missing" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
    FAILED=$((FAILED + 1))
    filesync_sync_iter_progress
    continue
  fi

  if ! has_master_file_sync_marker "$FULL_MASTER_PATH" 2>/dev/null; then
    file_sync_print_sync_skip_line "⚠" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH" "no master marker"
    SKIPPED=$((SKIPPED + 1))
    filesync_sync_iter_progress
    continue
  fi

  if [[ -f "$FULL_LOCAL_PATH" ]]; then
    if ! has_clone_file_sync_marker "$FULL_LOCAL_PATH" 2>/dev/null; then
      if [[ "$FORCE" != true ]]; then
        file_sync_print_sync_skip_line "⚠" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH" "no clone marker (--force to overwrite)"
        SKIPPED=$((SKIPPED + 1))
        filesync_sync_iter_progress
        continue
      fi
    fi
  fi

  if [[ -f "$FULL_LOCAL_PATH" ]]; then
    EXPECTED_TMP=$(mktemp)
    if ! render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$EXPECTED_TMP"; then
      rm -f "$EXPECTED_TMP"
      file_sync_print_sync_action_line "${RED}✗${NC}" "${RED}" "could not render" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
      filesync_error "${LOCAL_PATH}: could not render clone from master ${REPO_NAME}/${REPO_FILE_PATH} (master file missing or unparsable filesync marker)"
      FAILED=$((FAILED + 1))
      filesync_sync_iter_progress
      continue
    fi
    set +e
    diff -q "$EXPECTED_TMP" "$FULL_LOCAL_PATH" >/dev/null 2>&1
    DIFF_RESULT=$?
    set -e
    rm -f "$EXPECTED_TMP"
    if [[ $DIFF_RESULT -eq 0 ]]; then
      [[ "$SHOWALL" == true ]] && file_sync_print_sync_action_line "${GREEN}✓${NC}" "${GREEN}" "Already in sync" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
      ALREADY_SYNCED=$((ALREADY_SYNCED + 1))
      if [[ "$DRY_RUN" != true ]]; then
        filesync_write_file_row "$FILESYNC_FILES_FILE" "$PROJECT_ROOT" "$LOCAL_PATH" "$FULL_MASTER_PATH" "synced"
      fi
      filesync_sync_iter_progress
      continue
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    file_sync_print_sync_action_line "${YELLOW}→${NC}" "${YELLOW}" "dry-run" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
  else
    mkdir -p "$(dirname "$FULL_LOCAL_PATH")"
    if ! render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$FULL_LOCAL_PATH"; then
      file_sync_print_sync_action_line "${RED}✗${NC}" "${RED}" "could not render" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
      filesync_error "${LOCAL_PATH}: could not render clone from master ${REPO_NAME}/${REPO_FILE_PATH} (master file missing or unparsable filesync marker)"
      FAILED=$((FAILED + 1))
      filesync_sync_iter_progress
      continue
    fi
    file_sync_print_sync_action_line "${GREEN}✓${NC}" "${GREEN}" "synced" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
    filesync_write_file_row "$FILESYNC_FILES_FILE" "$PROJECT_ROOT" "$LOCAL_PATH" "$FULL_MASTER_PATH" "synced"
  fi
  SYNCED=$((SYNCED + 1))

  filesync_sync_iter_progress
done < "$SYNC_ROWS_TSV"

filesync_progress_end

if [[ -n "$FILE_FRAGMENT" ]] && [[ "$FILE_PATH_MATCHES" -eq 0 ]]; then
  echo "" >&2
  filesync_print_no_file_rows_for_fragment "$FILE_FRAGMENT"
fi

SELECTED=$((FILE_PATH_MATCHES - STATUS_SKIPPED))
if [[ "$SELECTED" -lt 0 ]]; then
  SELECTED=0
fi
ATTEMPTED=$((SYNCED + ALREADY_SYNCED + SKIPPED + FAILED))
echo "Sync report: selected=$SELECTED attempted=$ATTEMPTED synced=$SYNCED already_in_sync=$ALREADY_SYNCED skipped=$SKIPPED status_skipped=$STATUS_SKIPPED failed=$FAILED" >&2

if [[ $FAILED -gt 0 ]]; then
  echo "" >&2
  echo -e "${RED}Failed: $FAILED${NC} ${WHITE}| Synced: $SYNCED | Already in sync: $ALREADY_SYNCED | Skipped: $SKIPPED | Status-filtered: $STATUS_SKIPPED${NC}" >&2
  filesync_error "exiting with status 1 because $FAILED file(s) failed to sync."
  exit 1
elif [[ "$DRY_RUN" == true ]]; then
  echo "" >&2
  if [[ $SYNCED -gt 0 ]]; then
    echo -e "${YELLOW}Dry run: $SYNCED files would be synced${NC}" >&2
  else
    echo -e "${GREEN}✓${NC} ${WHITE}Nothing to sync ($ALREADY_SYNCED already in sync, $STATUS_SKIPPED status-skipped)${NC}" >&2
  fi
else
  echo "" >&2
  if [[ $SYNCED -gt 0 ]]; then
    echo -e "${GREEN}✓ Success: $SYNCED files synced${NC}" >&2
  else
    echo -e "${GREEN}✓${NC} ${WHITE}Nothing to sync ($ALREADY_SYNCED already in sync, $STATUS_SKIPPED status-skipped)${NC}" >&2
  fi
fi

exit 0
