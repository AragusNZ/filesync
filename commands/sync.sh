#!/usr/bin/env bash
# Sync from master repos into project (updates .filesync/files.json rows).
# Usage: sync.sh [--repo=name] [--file=...] [--repo-file=...] [--all-files=...] [-c|--check] [--no-commit] ...
# Path fragments: same rules as filesync check (AND across --file / --repo-file / --all-files).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync sync [--repo=name] [--file=path_fragment ...] [--repo-file=path_fragment ...] [--all-files=path_fragment ...] [-c|--check] [--no-commit] [--dry-run] [-f|--force] [--showall] [--status=a,b,...] [--include-detached] [--move|--mv]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: s

Pull the latest content from master repos into this project and refresh each row's status in
.filesync/files.json.

Options:
  --repo=name            Only files tied to this repo
  --file=fragment        Match part of the local path (repeat for OR; combine with --repo as usual)
  --repo-file=fragment   Match part of the path inside the repo checkout
  --all-files=fragment   Match either local or repo path
  -c, --check            Run filesync check with the same filters before copying
  --no-commit            Write files in place this run (skip git branch/merge even if enabled for the repo)
  --dry-run              Show what would happen without writing files
  -f, --force            Include 'local newer' and 'conflict' rows (normally skipped)
  --showall              Print one line per file
  --status=a,b,...       Only rows in these states (OR). Tokens: filesync -h or man filesync
  --include-detached     Include detached rows (normally skipped)
  --move, --mv           If status is master_file_moved, move the local file to the new path first

When --status= is omitted: updates unset, sync_required, error_missing_local, and master_file_moved;
detached rows stay skipped unless you add --include-detached.

When a repo is set up for git-style updates (merge_using_git in the catalog) and this project is a
git repo with a clean working tree—nothing else modified except possibly .filesync/files.json—sync
may use a short side branch and merge so conflicts look like normal git merges. Otherwise it copies
from master into your tracked paths directly.

--no-commit always uses that direct copy for this run, even when git-style mode is on—useful when
you have other local changes and sync would otherwise ask for a clean tree (see filesync(1)).
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-banner.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/sync-git-merge.sh"

REPO_FILTER=""
declare -a FILE_FRAGMENTS=()
declare -a REPO_FILE_FRAGMENTS=()
declare -a ALL_FILES_FRAGMENTS=()
DRY_RUN=false
FORCE=false
STATUS_CSV=""
INCLUDE_DETACHED=false
SHOWALL=false
RUN_CHECK=false
SYNC_MOVE=false
NO_COMMIT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-commit) NO_COMMIT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --move|--mv)
      # shellcheck disable=SC2034
      SYNC_MOVE=true
      shift
      ;;
    -f|--force) FORCE=true; shift ;;
    --showall) SHOWALL=true; shift ;;
    -c|--check) RUN_CHECK=true; shift ;;
    --include-detached) INCLUDE_DETACHED=true; shift ;;
    --status=*) STATUS_CSV="${1#*=}"; shift ;;
    --repo=*)
      REPO_FILTER="${1#*=}"
      shift
      ;;
    --file=*)
      FILE_FRAGMENTS+=("${1#*=}")
      shift
      ;;
    --repo-file=*)
      REPO_FILE_FRAGMENTS+=("${1#*=}")
      shift
      ;;
    --all-files=*)
      ALL_FILES_FRAGMENTS+=("${1#*=}")
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
  esac
done

if [[ "$NO_COMMIT" == true ]]; then
  FILESYNC_SYNC_NO_COMMIT=1
fi

mapfile -t FILE_FRAGMENTS_nonempty < <(filesync_emit_nonempty_file_fragments FILE_FRAGMENTS)
if [[ ${#FILE_FRAGMENTS_nonempty[@]} -eq 0 ]]; then
  FRAGS_JSON='[]'
  FILE_FILTER_LABEL=""
else
  FRAGS_JSON=$(printf '%s\n' "${FILE_FRAGMENTS_nonempty[@]}" | jq -R . | jq -s .)
  FILE_FILTER_LABEL=$(IFS=', '; echo "${FILE_FRAGMENTS_nonempty[*]}")
fi

mapfile -t REPO_FILE_FRAGMENTS_nonempty < <(filesync_emit_nonempty_file_fragments REPO_FILE_FRAGMENTS)
if [[ ${#REPO_FILE_FRAGMENTS_nonempty[@]} -eq 0 ]]; then
  REPO_FRAGS_JSON='[]'
  REPO_FILE_FILTER_LABEL=""
else
  REPO_FRAGS_JSON=$(printf '%s\n' "${REPO_FILE_FRAGMENTS_nonempty[@]}" | jq -R . | jq -s .)
  REPO_FILE_FILTER_LABEL=$(IFS=', '; echo "${REPO_FILE_FRAGMENTS_nonempty[*]}")
fi

mapfile -t ALL_FILES_FRAGMENTS_nonempty < <(filesync_emit_nonempty_file_fragments ALL_FILES_FRAGMENTS)
if [[ ${#ALL_FILES_FRAGMENTS_nonempty[@]} -eq 0 ]]; then
  ALL_FRAGS_JSON='[]'
  ALL_FILES_FILTER_LABEL=""
else
  ALL_FRAGS_JSON=$(printf '%s\n' "${ALL_FILES_FRAGMENTS_nonempty[@]}" | jq -R . | jq -s .)
  ALL_FILES_FILTER_LABEL=$(IFS=', '; echo "${ALL_FILES_FRAGMENTS_nonempty[*]}")
fi

# For merge_using_git commit messages (see lib/sync-git-merge.sh).
FILESYNC_SYNC_COMMIT_OPTIONS_DESC=""
declare -a FILESYNC_SYNC_COMMIT_OPT_PARTS=()
[[ "$FORCE" == true ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("force")
[[ "$RUN_CHECK" == true ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("check")
[[ "$SYNC_MOVE" == true ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("move")
[[ "$INCLUDE_DETACHED" == true ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("include-detached")
[[ "$NO_COMMIT" == true ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("no-commit")
[[ -n "$REPO_FILTER" ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("repo=${REPO_FILTER}")
[[ -n "$STATUS_CSV" ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("status=${STATUS_CSV}")
[[ -n "$FILE_FILTER_LABEL" ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("file=${FILE_FILTER_LABEL}")
[[ -n "$REPO_FILE_FILTER_LABEL" ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("repo-file=${REPO_FILE_FILTER_LABEL}")
[[ -n "$ALL_FILES_FILTER_LABEL" ]] && FILESYNC_SYNC_COMMIT_OPT_PARTS+=("all-files=${ALL_FILES_FILTER_LABEL}")
if [[ ${#FILESYNC_SYNC_COMMIT_OPT_PARTS[@]} -gt 0 ]]; then
  FILESYNC_SYNC_COMMIT_OPTIONS_DESC=$(IFS=', '; echo "${FILESYNC_SYNC_COMMIT_OPT_PARTS[*]}")
  FILESYNC_SYNC_COMMIT_OPTIONS_DESC="${FILESYNC_SYNC_COMMIT_OPTIONS_DESC//\"/}"
fi
unset FILESYNC_SYNC_COMMIT_OPT_PARTS

if [[ "$RUN_CHECK" == true ]]; then
  CHECK_ARGS=()
  [[ -n "$REPO_FILTER" ]] && CHECK_ARGS+=("--repo=$REPO_FILTER")
  for _ff in "${FILE_FRAGMENTS[@]}"; do
    CHECK_ARGS+=(--file="$_ff")
  done
  for _ff in "${REPO_FILE_FRAGMENTS[@]}"; do
    CHECK_ARGS+=(--repo-file="$_ff")
  done
  for _ff in "${ALL_FILES_FRAGMENTS[@]}"; do
    CHECK_ARGS+=(--all-files="$_ff")
  done
  [[ -n "$STATUS_CSV" ]] && CHECK_ARGS+=("--status=$STATUS_CSV")
  if ! "$_CMD_ROOT/check.sh" "${CHECK_ARGS[@]}"; then
    filesync_error "--check failed; not running sync."
    exit 1
  fi
  filesync_assemble_state_to "$FILESYNC_STATE_FILE" || filesync_die "could not reload project configuration after --check"
fi

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
    if [[ "$status" == "master_file_moved" ]]; then
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
  filesync_sync_git_emergency_cleanup "${PROJECT_ROOT:-}" || true
  # shellcheck disable=SC2317
  filesync_progress_end || true
  # shellcheck disable=SC2317
  rm -f "${FILESYNC_STATE_FILE:-}" "${SYNC_ROWS_TSV:-}" "${SYNC_ROWS_SORTED:-}"
  # shellcheck disable=SC2317
  rm -rf "${FILESYNC_CLONED_TEMP_DIRS[@]:-}"
}
trap cleanup_sync_exit EXIT

filesync_sync_git_reset_state

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
filesync_print_filter_context "$REPO_FILTER" "$FILE_FILTER_LABEL" "$REPO_FILE_FILTER_LABEL" "$ALL_FILES_FILTER_LABEL" "$STATUS_CSV" "$INCLUDE_DETACHED" 1 "$FORCE"
filesync_print_sync_showall_banner "$SHOWALL"
echo "" >&2

SYNC_ROWS_TSV=$(mktemp)
SYNC_ROWS_SORTED=$(mktemp)
filesync_config_file_rows_tsv_to "$SYNC_ROWS_TSV" "$CONFIG_FILE" "$REPO_FILTER" "$FRAGS_JSON" "$REPO_FRAGS_JSON" "$ALL_FRAGS_JSON"
LC_ALL=C sort -t $'\t' -k3,3 -s "$SYNC_ROWS_TSV" >"$SYNC_ROWS_SORTED"
FILES_WORK_COUNT=$(wc -l < "$SYNC_ROWS_SORTED")
FILES_WORK_COUNT="${FILES_WORK_COUNT//[[:space:]]/}"

if [[ "$FILES_WORK_COUNT" -eq 0 ]] && filesync_files_only_blocked_by_check_sync "$CONFIG_FILE" "$REPO_FILTER" "$FRAGS_JSON" "$REPO_FRAGS_JSON" "$ALL_FRAGS_JSON"; then
  filesync_print_disabled_hint
  exit 0
fi

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

while IFS=$'\t' read -r i REPO_ID REPO_NAME LOCAL_PATH REPO_FILE_PATH ROW_STATUS _last_sync_unused; do
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

  FULL_MASTER_PATH="$REPO_ROOT/$REPO_FILE_PATH"

  if [[ "$SYNC_MOVE" == true ]] && [[ "$ROW_STATUS" == "master_file_moved" ]] && [[ "$LOCAL_PATH" != "$REPO_FILE_PATH" ]]; then
    if [[ ! -f "$FULL_MASTER_PATH" ]]; then
      file_sync_print_sync_action_line "${RED}✗${NC}" "${RED}" "source missing (--move)" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
      FAILED=$((FAILED + 1))
      filesync_sync_iter_progress
      continue
    fi
    _src_move="$PROJECT_ROOT/$LOCAL_PATH"
    _dst_move="$PROJECT_ROOT/$REPO_FILE_PATH"
    if [[ "$DRY_RUN" == true ]]; then
      file_sync_print_sync_action_line "${YELLOW}→${NC}" "${YELLOW}" "dry-run move -> $REPO_FILE_PATH" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
      filesync_sync_iter_progress
      continue
    else
      [[ -f "$_src_move" ]] || {
        file_sync_print_sync_action_line "${RED}✗${NC}" "${RED}" "local missing (--move)" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
        FAILED=$((FAILED + 1))
        filesync_sync_iter_progress
        continue
      }
      if [[ -e "$_dst_move" ]]; then
        if [[ "$(filesync_canonical_existing "$_src_move" 2>/dev/null)" != "$(filesync_canonical_existing "$_dst_move" 2>/dev/null)" ]]; then
          file_sync_print_sync_action_line "${RED}✗${NC}" "${RED}" "move dest exists" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
          FAILED=$((FAILED + 1))
          filesync_sync_iter_progress
          continue
        fi
      fi
      mkdir -p "$(dirname "$_dst_move")"
      mv "$_src_move" "$_dst_move"
      _now_m=$(file_sync_now_iso)
      jq --argjson idx "$i" --arg nlp "$REPO_FILE_PATH" --arg now "$_now_m" \
        '(.[$idx] |= (. + {local_path: $nlp, sync_status: "sync_required", last_check_at: $now}))' \
        "$FILESYNC_FILES_FILE" >"${FILESYNC_FILES_FILE}.tmp"
      mv "${FILESYNC_FILES_FILE}.tmp" "$FILESYNC_FILES_FILE"
      filesync_assemble_state_to "$FILESYNC_STATE_FILE" || filesync_die "could not reload project configuration after --move"
      LOCAL_PATH="$REPO_FILE_PATH"
      ROW_STATUS="sync_required"
      file_sync_print_sync_action_line "${GREEN}✓${NC}" "${GREEN}" "moved local to $REPO_FILE_PATH" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
    fi
  fi

  if ! filesync_sync_git_repo_transition "$PROJECT_ROOT" "$FILESYNC_FILES_FILE" "$CONFIG_FILE" "$REPO_NAME"; then
    FAILED=$((FAILED + 1))
    filesync_sync_iter_progress
    continue
  fi

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
        file_sync_print_sync_skip_line "⚠" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH" "no clone marker (-f/--force to overwrite)"
        SKIPPED=$((SKIPPED + 1))
        filesync_sync_iter_progress
        continue
      fi
    fi
  fi

  if [[ -f "$FULL_LOCAL_PATH" ]]; then
    EXPECTED_TMP=$(mktemp)
    _rid_render="${REPO_ID}"
    if [[ -f "$FULL_LOCAL_PATH" ]] && ! grep -q 'repo_id=' "$FULL_LOCAL_PATH"; then
      _rid_render=""
    fi
    if ! render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$EXPECTED_TMP" "$_rid_render"; then
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
        if filesync_sync_git_use_merge_path "$CONFIG_FILE" "$REPO_NAME"; then
          filesync_sync_git_defer_already_synced "$LOCAL_PATH" "$FULL_MASTER_PATH"
        else
          filesync_write_file_row "$FILESYNC_FILES_FILE" "$PROJECT_ROOT" "$LOCAL_PATH" "$FULL_MASTER_PATH" "synced"
        fi
      fi
      filesync_sync_iter_progress
      continue
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    file_sync_print_sync_action_line "${YELLOW}→${NC}" "${YELLOW}" "dry-run" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
  else
    mkdir -p "$(dirname "$FULL_LOCAL_PATH")"
    if filesync_sync_git_use_merge_path "$CONFIG_FILE" "$REPO_NAME"; then
      if ! filesync_sync_git_start_batch "$PROJECT_ROOT" "$REPO_NAME"; then
        file_sync_print_sync_action_line "${RED}✗${NC}" "${RED}" "git batch start failed" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
        filesync_error "${LOCAL_PATH}: could not create temporary sync branch (see messages above)"
        FAILED=$((FAILED + 1))
        filesync_sync_iter_progress
        continue
      fi
    fi
    _rid_render="${REPO_ID}"
    if [[ -f "$FULL_LOCAL_PATH" ]] && ! grep -q 'repo_id=' "$FULL_LOCAL_PATH"; then
      _rid_render=""
    fi
    if ! render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$FULL_LOCAL_PATH" "$_rid_render"; then
      file_sync_print_sync_action_line "${RED}✗${NC}" "${RED}" "could not render" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
      filesync_error "${LOCAL_PATH}: could not render clone from master ${REPO_NAME}/${REPO_FILE_PATH} (master file missing or unparsable filesync marker)"
      if [[ "${FILESYNC_SYNC_GIT_ACTIVE_REPO:-}" == "$REPO_NAME" ]]; then
        filesync_sync_git_abort_open_batch "$PROJECT_ROOT"
      fi
      FAILED=$((FAILED + 1))
      filesync_sync_iter_progress
      continue
    fi
    file_sync_print_sync_action_line "${GREEN}✓${NC}" "${GREEN}" "synced" "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH"
    if filesync_sync_git_use_merge_path "$CONFIG_FILE" "$REPO_NAME"; then
      filesync_sync_git_record_pending "$LOCAL_PATH" "$FULL_MASTER_PATH" "$REPO_ID"
    else
      filesync_write_file_row "$FILESYNC_FILES_FILE" "$PROJECT_ROOT" "$LOCAL_PATH" "$FULL_MASTER_PATH" "synced"
    fi
  fi
  SYNCED=$((SYNCED + 1))

  filesync_sync_iter_progress
done < "$SYNC_ROWS_SORTED"

if ! filesync_sync_git_finish_last_repo "$PROJECT_ROOT" "$FILESYNC_FILES_FILE" "$CONFIG_FILE"; then
  FAILED=$((FAILED + 1))
fi

filesync_progress_end

if [[ "$FILE_PATH_MATCHES" -eq 0 ]]; then
  echo "" >&2
  if [[ -n "$FILE_FILTER_LABEL" ]] || [[ -n "$REPO_FILE_FILTER_LABEL" ]] || [[ -n "$ALL_FILES_FILTER_LABEL" ]]; then
    filesync_print_no_file_rows_path_filters "$FILE_FILTER_LABEL" "$REPO_FILE_FILTER_LABEL" "$ALL_FILES_FILTER_LABEL"
  fi
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
