#!/usr/bin/env bash
# Check synced files; update .filesync/files.json row status (incl. last_check_at per row).
# Usage: check.sh [--repo=name] [--file=...] [--repo-file=...] [--all-files=...] [--status=a,b,...]
# Path fragments: --file= local_path; --repo-file= repo_file_path; --all-files= either (repeat for OR within each).
# Dimensions combine with AND. Omit a dimension (or pass only blank values) to leave it unconstrained.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync check [--repo=name] [--file=path_fragment ...] [--repo-file=path_fragment ...] [--all-files=path_fragment ...] [--status=a,b,...]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: c

Verify mappings: compare tracked files to the repo checkout and disk, then update each row's status
(and last_check_at) in .filesync/files.json.

Filters (path rules match sync; repeat a flag for OR within that dimension; combine dimensions with AND):

  --repo=name              Only rows for this repo
  --file=fragment          Substring on local path
  --repo-file=fragment     Substring on path inside the checkout
  --all-files=fragment     Match either local or repo path
  --status=a,b,...         Only these row states (OR). Tokens: filesync -h or man filesync

Note:
  If every matching repo has checking disabled (check_sync_enabled false), filesync prints a hint and
  exits without scanning.
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

col_st() { file_sync_status_color "$1"; }

REPO_FILTER=""
declare -a FILE_FRAGMENTS=()
declare -a REPO_FILE_FRAGMENTS=()
declare -a ALL_FILES_FRAGMENTS=()
STATUS_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --status=*)
      STATUS_FILTER="${1#*=}"
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

# shellcheck disable=SC2034
declare -A FILESYNC_REPO_DIR_CACHE
# shellcheck disable=SC2034
declare -a FILESYNC_CLONED_TEMP_DIRS

append_patch() {
  echo "$1" >> "$PATCH_LINES_FILE"
}

append_patch_with_status() {
  local status="$1"
  local patch_json="$2"
  append_patch "$patch_json"
  UPDATED_ROWS=$((UPDATED_ROWS + 1))
  filesync_counts_inc CHECK_STATUS_COUNTS "$status"
}

# JSON array of strings for jq --argjson (empty -> []).
check_marker_warn_codes_json() {
  if [[ ${#CHECK_MARKER_WARN_CODES[@]} -eq 0 ]]; then
    printf '%s' '[]'
    return
  fi
  printf '%s\n' "${CHECK_MARKER_WARN_CODES[@]}" | jq -R . | jq -s .
}

# Both files must exist. Sets CHECK_MARKER_WARN_CODES (shown on the row line like list files).
check_collect_marker_warnings() {
  CHECK_MARKER_WARN_CODES=()
  if has_clone_file_sync_marker "$FULL_MASTER_PATH" 2>/dev/null; then
    CHECK_MARKER_WARN_CODES+=(master_kind_clone)
  elif ! has_master_file_sync_marker "$FULL_MASTER_PATH" 2>/dev/null; then
    CHECK_MARKER_WARN_CODES+=(master_no_master_marker)
  fi
  if has_master_file_sync_marker "$FULL_LOCAL_PATH" 2>/dev/null; then
    CHECK_MARKER_WARN_CODES+=(local_kind_master)
  fi
  if ! has_clone_file_sync_marker "$FULL_LOCAL_PATH" 2>/dev/null; then
    CHECK_MARKER_WARN_CODES+=(local_no_clone_marker)
  fi
}

check_marker_warnings_csv() {
  if [[ ${#CHECK_MARKER_WARN_CODES[@]} -eq 0 ]]; then
    printf ''
    return
  fi
  (IFS=,; printf '%s' "${CHECK_MARKER_WARN_CODES[*]}")
}

BLOCKING_ISSUES=0
CHECKED=0
MARKER_WARN_ROWS=0
UPDATED_ROWS=0
# shellcheck disable=SC2034  # Used via nameref in filesync_counts_inc/render helpers.
declare -A CHECK_STATUS_COUNTS=()

filesync_print_check_banner
filesync_print_filter_context "$REPO_FILTER" "$FILE_FILTER_LABEL" "$REPO_FILE_FILTER_LABEL" "$ALL_FILES_FILTER_LABEL" "$STATUS_FILTER" false 0
echo "" >&2

PATCH_LINES_FILE=$(mktemp)
CHECK_ROWS_TSV=$(mktemp)

cleanup_verify_exit() {
  # shellcheck disable=SC2317
  filesync_progress_end || true
  # shellcheck disable=SC2317
  rm -f "${PATCH_LINES_FILE:-}" "${CHECK_ROWS_TSV:-}" "${FILESYNC_STATE_FILE:-}"
  # shellcheck disable=SC2317
  rm -rf "${FILESYNC_CLONED_TEMP_DIRS[@]:-}"
}
trap cleanup_verify_exit EXIT

filesync_config_file_rows_tsv_to "$CHECK_ROWS_TSV" "$CONFIG_FILE" "$REPO_FILTER" "$FRAGS_JSON" "$REPO_FRAGS_JSON" "$ALL_FRAGS_JSON"
FILES_WORK_COUNT=$(wc -l < "$CHECK_ROWS_TSV")
FILES_WORK_COUNT="${FILES_WORK_COUNT//[[:space:]]/}"

if [[ "$FILES_WORK_COUNT" -eq 0 ]] && filesync_files_only_blocked_by_check_sync "$CONFIG_FILE" "$REPO_FILTER" "$FRAGS_JSON" "$REPO_FRAGS_JSON" "$ALL_FRAGS_JSON"; then
  filesync_print_disabled_hint
  exit 0
fi

if filesync_progress_want "$FILES_WORK_COUNT"; then
  filesync_progress_begin "$FILES_WORK_COUNT"
fi

CHECK_ROW_PROGRESS=0
filesync_check_iter_progress() {
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    CHECK_ROW_PROGRESS=$((CHECK_ROW_PROGRESS + 1))
    filesync_progress_update "$CHECK_ROW_PROGRESS"
  fi
}

while IFS=$'\t' read -r i REPO_ID REPO_NAME LOCAL_PATH REPO_FILE_PATH PRIOR_STATUS LAST_SYNC_RAW; do

  NOW_ISO=$(file_sync_now_iso)
  NOW_E=$(file_sync_now_epoch)

  if [[ -z "$REPO_NAME" ]] || [[ "$REPO_NAME" == "null" ]]; then
    filesync_print_config_error_invalid_repo_name "$i"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch_with_status "error_invalid_repo" "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" --argjson cw '[]' '{i: $idx, last_check_at: $now, sync_status: "error_invalid_repo", check_marker_warnings: $cw}')"
    filesync_check_iter_progress
    continue
  fi

  if [[ -n "$REPO_FILTER" ]] && [[ "$REPO_NAME" != "$REPO_FILTER" ]]; then
    filesync_check_iter_progress
    continue
  fi

  if ! filesync_row_matches_path_filter_groups "$LOCAL_PATH" "$REPO_FILE_PATH" FILE_FRAGMENTS REPO_FILE_FRAGMENTS ALL_FILES_FRAGMENTS; then
    filesync_check_iter_progress
    continue
  fi

  if [[ -n "$STATUS_FILTER" ]] && ! file_sync_status_matches_csv "$PRIOR_STATUS" "$STATUS_FILTER" false; then
    filesync_check_iter_progress
    continue
  fi

  if [[ -z "$LOCAL_PATH" ]] || [[ "$LOCAL_PATH" == "null" ]]; then
    filesync_print_config_error_invalid_local_path "$i"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch_with_status "error_invalid_local_path" "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" --argjson cw '[]' '{i: $idx, last_check_at: $now, sync_status: "error_invalid_local_path", check_marker_warnings: $cw}')"
    filesync_check_iter_progress
    continue
  fi

  if [[ -z "$REPO_FILE_PATH" ]] || [[ "$REPO_FILE_PATH" == "null" ]]; then
    filesync_print_config_error_invalid_repo_file_path "$LOCAL_PATH"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch_with_status "error_invalid_repo_path" "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" --argjson cw '[]' '{i: $idx, last_check_at: $now, sync_status: "error_invalid_repo_path", check_marker_warnings: $cw}')"
    filesync_check_iter_progress
    continue
  fi

  REPO_ROOT=""
  if ! REPO_ROOT=$(filesync_get_repo_dir "$REPO_NAME"); then
    echo -e "${RED}✗${NC} ${WHITE}$LOCAL_PATH: Could not resolve repo $REPO_NAME${NC}" >&2
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch_with_status "error_repo_unavailable" "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" --argjson cw '[]' '{i: $idx, last_check_at: $now, sync_status: "error_repo_unavailable", check_marker_warnings: $cw}')"
    filesync_check_iter_progress
    continue
  fi

  # After a fresh git clone, master files often have mtimes at clone completion. NOW_E was
  # captured at loop start (before clone), so it can be older than REPO_E and falsely yield
  # sync_required despite identical content (file_sync_compute_status requires now>=repo).
  NOW_ISO=$(file_sync_now_iso)
  NOW_E=$(file_sync_now_epoch)

  FULL_LOCAL_PATH="$PROJECT_ROOT/$LOCAL_PATH"
  FULL_MASTER_PATH="$REPO_ROOT/$REPO_FILE_PATH"

  REPO_ISO=""
  LOCAL_ISO=""
  if [[ -f "$FULL_MASTER_PATH" ]]; then
    REPO_ISO=$(file_sync_mtime_iso "$FULL_MASTER_PATH")
  fi
  if [[ -f "$FULL_LOCAL_PATH" ]]; then
    LOCAL_ISO=$(file_sync_mtime_iso "$FULL_LOCAL_PATH")
  fi

  REPO_E=0
  LOCAL_E=0
  [[ -n "$REPO_ISO" ]] && REPO_E=$(file_sync_parse_to_epoch "$REPO_ISO")
  [[ -n "$LOCAL_ISO" ]] && LOCAL_E=$(file_sync_parse_to_epoch "$LOCAL_ISO")

  if [[ "$PRIOR_STATUS" == "detached" ]]; then
    CHECKED=$((CHECKED + 1))
    append_patch_with_status "detached" "$(jq -nc \
      --argjson idx "$i" \
      --arg now "$NOW_ISO" \
      --arg rs "${REPO_ISO:-}" \
      --arg ls "${LOCAL_ISO:-}" \
      --argjson cw '[]' \
      '{
        i: $idx,
        last_check_at: $now,
        sync_status: "detached",
        repo_file_modified_at: (if $rs == "" then null else $rs end),
        local_file_modified_at: (if $ls == "" then null else $ls end),
        check_marker_warnings: $cw
      }')"
    file_sync_print_file_row "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH" "detached" ""
    filesync_check_iter_progress
    continue
  fi

  if [[ ! -f "$FULL_MASTER_PATH" ]]; then
    echo -e "$(col_st error_missing_master)${RED}✗${NC} ${WHITE}$LOCAL_PATH: Source not found in $REPO_NAME ($REPO_FILE_PATH)${NC}" >&2
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch_with_status "error_missing_master" "$(jq -nc \
      --argjson idx "$i" \
      --arg now "$NOW_ISO" \
      --arg ls "${LOCAL_ISO:-}" \
      --argjson cw '[]' \
      '{
        i: $idx,
        last_check_at: $now,
        sync_status: "error_missing_master",
        repo_file_modified_at: null,
        local_file_modified_at: (if $ls == "" then null else $ls end),
        check_marker_warnings: $cw
      }')"
    filesync_check_iter_progress
    continue
  fi

  if [[ ! -f "$FULL_LOCAL_PATH" ]]; then
    echo -e "$(col_st error_missing_local)${RED}✗${NC} ${WHITE}$LOCAL_PATH: Local file not found${NC}" >&2
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch_with_status "error_missing_local" "$(jq -nc \
      --argjson idx "$i" \
      --arg now "$NOW_ISO" \
      --arg rs "${REPO_ISO:-}" \
      --argjson cw '[]' \
      '{
        i: $idx,
        last_check_at: $now,
        sync_status: "error_missing_local",
        repo_file_modified_at: (if $rs == "" then null else $rs end),
        local_file_modified_at: null,
        check_marker_warnings: $cw
      }')"
    filesync_check_iter_progress
    continue
  fi

  check_collect_marker_warnings
  [[ ${#CHECK_MARKER_WARN_CODES[@]} -gt 0 ]] && MARKER_WARN_ROWS=$((MARKER_WARN_ROWS + 1))

  EXPECTED_TMP=$(mktemp)
  _rid_render="${REPO_ID}"
  if [[ -f "$FULL_LOCAL_PATH" ]] && ! grep -q 'repo_id=' "$FULL_LOCAL_PATH"; then
    _rid_render=""
  fi
  if ! render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$EXPECTED_TMP" "$_rid_render"; then
    rm -f "$EXPECTED_TMP"
    filesync_warn "${LOCAL_PATH}: could not render clone from master ${REPO_NAME}/${REPO_FILE_PATH} (unparsable or missing filesync marker line)"
    CHECKED=$((CHECKED + 1))
    _cw_json="$(check_marker_warn_codes_json)"
    append_patch_with_status "error_master_marker" "$(jq -nc \
      --argjson idx "$i" \
      --arg now "$NOW_ISO" \
      --arg rs "${REPO_ISO:-}" \
      --arg ls "${LOCAL_ISO:-}" \
      --argjson cw "$_cw_json" \
      '{
        i: $idx,
        last_check_at: $now,
        sync_status: "error_master_marker",
        repo_file_modified_at: (if $rs == "" then null else $rs end),
        local_file_modified_at: (if $ls == "" then null else $ls end),
        check_marker_warnings: $cw
      }')"
    file_sync_print_file_row "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH" "error_master_marker" "$(check_marker_warnings_csv)"
    filesync_check_iter_progress
    continue
  fi
  set +e
  diff -q "$EXPECTED_TMP" "$FULL_LOCAL_PATH" >/dev/null 2>&1
  DIFF_RESULT=$?
  set -e
  rm -f "$EXPECTED_TMP"

  DIFF_OK=0
  [[ $DIFF_RESULT -eq 0 ]] && DIFF_OK=1

  LAST_SYNC_E=$(file_sync_parse_to_epoch "$LAST_SYNC_RAW")

  STATUS=$(file_sync_compute_status "$DIFF_OK" "$REPO_E" "$LOCAL_E" "$LAST_SYNC_E" "$NOW_E")

  if [[ "$PRIOR_STATUS" == "master_file_moved" ]] && [[ "$LOCAL_PATH" != "$REPO_FILE_PATH" ]] && [[ ! "$STATUS" =~ ^error_ ]] && [[ "$STATUS" != "conflict" ]]; then
    STATUS="master_file_moved"
  fi

  CHECKED=$((CHECKED + 1))

  _cw_json="$(check_marker_warn_codes_json)"
  append_patch_with_status "$STATUS" "$(jq -nc \
    --argjson idx "$i" \
    --arg now "$NOW_ISO" \
    --arg rs "${REPO_ISO:-}" \
    --arg ls "${LOCAL_ISO:-}" \
    --arg st "$STATUS" \
    --argjson cw "$_cw_json" \
    '{
      i: $idx,
      last_check_at: $now,
      sync_status: $st,
      repo_file_modified_at: (if $rs == "" then null else $rs end),
      local_file_modified_at: (if $ls == "" then null else $ls end),
      check_marker_warnings: $cw
    }')"

  if [[ "$STATUS" == "conflict" ]] || [[ "$STATUS" =~ ^error_ ]]; then
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
  fi

  file_sync_print_file_row "$REPO_NAME" "$REPO_FILE_PATH" "$LOCAL_PATH" "$STATUS" "$(check_marker_warnings_csv)"

  filesync_check_iter_progress
done < "$CHECK_ROWS_TSV"

filesync_progress_end

if [[ -s "$PATCH_LINES_FILE" ]]; then
  jq --slurpfile p <(jq -s '.' "$PATCH_LINES_FILE") '
    reduce $p[0][] as $patch (.;
      .[$patch.i] = (.[$patch.i] * ($patch | del(.i)))
    )
  ' "$FILESYNC_FILES_FILE" > "${FILESYNC_FILES_FILE}.tmp"
  mv "${FILESYNC_FILES_FILE}.tmp" "$FILESYNC_FILES_FILE"
fi

echo "" >&2
if [[ "$CHECKED" -eq 0 ]] && { [[ -n "$FILE_FILTER_LABEL" ]] || [[ -n "$REPO_FILE_FILTER_LABEL" ]] || [[ -n "$ALL_FILES_FILTER_LABEL" ]]; }; then
  filesync_print_no_file_rows_path_filters "$FILE_FILTER_LABEL" "$REPO_FILE_FILTER_LABEL" "$ALL_FILES_FILTER_LABEL"
fi
if [[ -n "$STATUS_FILTER" ]] && [[ "$CHECKED" -eq 0 ]]; then
  filesync_print_no_file_rows_for_status "$STATUS_FILTER"
fi
if [[ "$MARKER_WARN_ROWS" -gt 0 ]]; then
  echo -e "${YELLOW}Marker warning(s) on $MARKER_WARN_ROWS file row(s) (see ⚠ on lines above; codes in .filesync/files.json check_marker_warnings).${NC}" >&2
fi
if [[ "$UPDATED_ROWS" -gt 0 ]]; then
  filesync_print_status_summary "rows updated" "$UPDATED_ROWS" CHECK_STATUS_COUNTS
fi
if [[ $BLOCKING_ISSUES -gt 0 ]]; then
  echo -e "${RED}Check completed with $BLOCKING_ISSUES blocking issue(s).${NC} ${WHITE}Rows updated: $CHECKED${NC}" >&2
  filesync_error "exiting with status 1 because of $BLOCKING_ISSUES blocking issue(s)."
  exit 1
fi

echo -e "${GREEN}✓${NC} ${WHITE}Check OK ($CHECKED files updated).${NC}" >&2
exit 0
