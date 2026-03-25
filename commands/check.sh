#!/usr/bin/env bash
# Check synced files; update .filesync/files.json and .filesync/config.json (last_check_at).
# Usage: check.sh [--repo=name] [--file=path_fragment] [--status=a,b,...]
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

col_st() { file_sync_status_color "$1"; }

REPO_FILTER=""
FILE_FRAGMENT=""
STATUS_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo=*)
      REPO_FILTER="${1#*=}"
      shift
      ;;
    --file=*)
      FILE_FRAGMENT="${1#*=}"
      shift
      ;;
    --status=*)
      STATUS_FILTER="${1#*=}"
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync check [--repo=name] [--file=path_fragment] [--status=a,b,...]" >&2
      exit 1
      ;;
    *)
      echo -e "${RED}Unexpected argument: $1${NC}" >&2
      echo "Usage: filesync check [--repo=name] [--file=path_fragment] [--status=a,b,...]" >&2
      exit 1
      ;;
  esac
done

if ! jq -e '.file_sync_enabled == true' "$CONFIG_FILE" &>/dev/null; then
  filesync_print_disabled_hint
  exit 0
fi

# shellcheck disable=SC2034
declare -A FILESYNC_REPO_DIR_CACHE
# shellcheck disable=SC2034
declare -a FILESYNC_CLONED_TEMP_DIRS

append_patch() {
  echo "$1" >> "$PATCH_LINES_FILE"
}

# JSON array of strings for jq --argjson (empty -> []).
check_marker_warn_codes_json() {
  if [[ ${#CHECK_MARKER_WARN_CODES[@]} -eq 0 ]]; then
    printf '%s' '[]'
    return
  fi
  printf '%s\n' "${CHECK_MARKER_WARN_CODES[@]}" | jq -R . | jq -s .
}

# Both files must exist. Sets CHECK_MARKER_WARN_CODES (shown on the row line like list-files).
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

filesync_print_check_banner
filesync_print_filter_context "$REPO_FILTER" "$FILE_FRAGMENT" "$STATUS_FILTER" false 0
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

filesync_config_file_rows_tsv_to "$CHECK_ROWS_TSV" "$CONFIG_FILE" "$REPO_FILTER" "$FILE_FRAGMENT"
FILES_WORK_COUNT=$(wc -l < "$CHECK_ROWS_TSV")
FILES_WORK_COUNT="${FILES_WORK_COUNT//[[:space:]]/}"

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

while IFS=$'\t' read -r i REPO_NAME LOCAL_PATH REPO_FILE_PATH PRIOR_STATUS LAST_SYNC_RAW; do

  NOW_ISO=$(file_sync_now_iso)
  NOW_E=$(file_sync_now_epoch)

  if [[ -z "$REPO_NAME" ]] || [[ "$REPO_NAME" == "null" ]]; then
    filesync_print_config_error_invalid_repo_name "$i"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" --argjson cw '[]' '{i: $idx, last_check_at: $now, sync_status: "error_invalid_repo", check_marker_warnings: $cw}')"
    filesync_check_iter_progress
    continue
  fi

  if [[ -n "$REPO_FILTER" ]] && [[ "$REPO_NAME" != "$REPO_FILTER" ]]; then
    filesync_check_iter_progress
    continue
  fi

  if ! filesync_file_matches_fragment "$FILE_FRAGMENT" "$LOCAL_PATH" "$REPO_FILE_PATH"; then
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
    append_patch "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" --argjson cw '[]' '{i: $idx, last_check_at: $now, sync_status: "error_invalid_local_path", check_marker_warnings: $cw}')"
    filesync_check_iter_progress
    continue
  fi

  if [[ -z "$REPO_FILE_PATH" ]] || [[ "$REPO_FILE_PATH" == "null" ]]; then
    filesync_print_config_error_invalid_repo_file_path "$LOCAL_PATH"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" --argjson cw '[]' '{i: $idx, last_check_at: $now, sync_status: "error_invalid_repo_path", check_marker_warnings: $cw}')"
    filesync_check_iter_progress
    continue
  fi

  REPO_ROOT=""
  if ! REPO_ROOT=$(filesync_get_repo_dir "$REPO_NAME"); then
    echo -e "${RED}✗${NC} ${WHITE}$LOCAL_PATH: Could not resolve repo $REPO_NAME${NC}" >&2
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" --argjson cw '[]' '{i: $idx, last_check_at: $now, sync_status: "error_repo_unavailable", check_marker_warnings: $cw}')"
    filesync_check_iter_progress
    continue
  fi

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
    append_patch "$(jq -nc \
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
    append_patch "$(jq -nc \
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
    append_patch "$(jq -nc \
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
  if ! render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$EXPECTED_TMP"; then
    rm -f "$EXPECTED_TMP"
    filesync_warn "${LOCAL_PATH}: could not render clone from master ${REPO_NAME}/${REPO_FILE_PATH} (unparsable or missing filesync marker line)"
    CHECKED=$((CHECKED + 1))
    _cw_json="$(check_marker_warn_codes_json)"
    append_patch "$(jq -nc \
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

  CHECKED=$((CHECKED + 1))

  _cw_json="$(check_marker_warn_codes_json)"
  append_patch "$(jq -nc \
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

ROOT_NOW=$(file_sync_now_iso)

if [[ -s "$PATCH_LINES_FILE" ]]; then
  jq --slurpfile p <(jq -s '.' "$PATCH_LINES_FILE") '
    reduce $p[0][] as $patch (.;
      .[$patch.i] = (.[$patch.i] * ($patch | del(.i)))
    )
  ' "$FILESYNC_FILES_FILE" > "${FILESYNC_FILES_FILE}.tmp"
  mv "${FILESYNC_FILES_FILE}.tmp" "$FILESYNC_FILES_FILE"
  filesync_user_config_set_last_check_at "$ROOT_NOW"
fi

echo "" >&2
if [[ -n "$FILE_FRAGMENT" ]] && [[ "$CHECKED" -eq 0 ]]; then
  filesync_print_no_file_rows_for_fragment "$FILE_FRAGMENT"
fi
if [[ -n "$STATUS_FILTER" ]] && [[ "$CHECKED" -eq 0 ]]; then
  filesync_print_no_file_rows_for_status "$STATUS_FILTER"
fi
if [[ "$MARKER_WARN_ROWS" -gt 0 ]]; then
  echo -e "${YELLOW}Marker warning(s) on $MARKER_WARN_ROWS file row(s) (see ⚠ on lines above; codes in .filesync/files.json check_marker_warnings).${NC}" >&2
fi
if [[ $BLOCKING_ISSUES -gt 0 ]]; then
  echo -e "${RED}Check completed with $BLOCKING_ISSUES blocking issue(s).${NC} ${WHITE}Rows updated: $CHECKED${NC}" >&2
  filesync_error "exiting with status 1 because of $BLOCKING_ISSUES blocking issue(s)."
  exit 1
fi

echo -e "${GREEN}✓${NC} ${WHITE}Check OK ($CHECKED files updated).${NC}" >&2
exit 0
