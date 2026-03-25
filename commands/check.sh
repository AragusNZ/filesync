#!/usr/bin/env bash
# Check synced files; update .filesync/files.json and .filesync/config.json (last_check_at).
# Usage: check.sh [--repo=name] [--file=path_fragment]
# Path fragment: substring match on local_path or repo_file_path (after optional --repo filter).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

col_st() { file_sync_status_color "$1"; }
rst() { file_sync_color_reset; }

REPO_FILTER=""
FILE_FRAGMENT=""
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
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync check [--repo=name] [--file=path_fragment]" >&2
      exit 1
      ;;
    *)
      echo -e "${RED}Unexpected argument: $1${NC}" >&2
      echo "Usage: filesync check [--repo=name] [--file=path_fragment]" >&2
      exit 1
      ;;
  esac
done

if ! jq -e '.file_sync_enabled == true' "$CONFIG_FILE" &>/dev/null; then
  echo -e "${YELLOW}filesync is disabled. Run 'filesync enable' to enable.${NC}"
  exit 0
fi

# shellcheck disable=SC2034
declare -A FILESYNC_REPO_DIR_CACHE
# shellcheck disable=SC2034
declare -a FILESYNC_CLONED_TEMP_DIRS

append_patch() {
  echo "$1" >> "$PATCH_LINES_FILE"
}

BLOCKING_ISSUES=0
CHECKED=0

echo -e "${CYAN}Checking synced files (updating .filesync)...${NC}"
[[ -n "$REPO_FILTER" ]] && echo -e "${CYAN}Filter: --repo=$REPO_FILTER${NC}"
[[ -n "$FILE_FRAGMENT" ]] && echo -e "${CYAN}Filter: --file= substring on local_path or repo_file_path: ${FILE_FRAGMENT}${NC}"
echo ""

PATCH_LINES_FILE=$(mktemp)

cleanup_verify_exit() {
  # shellcheck disable=SC2317
  rm -f "${PATCH_LINES_FILE:-}" "${FILESYNC_STATE_FILE:-}"
  # shellcheck disable=SC2317
  rm -rf "${FILESYNC_CLONED_TEMP_DIRS[@]:-}"
}
trap cleanup_verify_exit EXIT

FILES_COUNT=$(jq '.files | length' "$CONFIG_FILE")

for ((i=0; i<FILES_COUNT; i++)); do
  set +e
  REPO_NAME=$(jq -r ".files[$i].repo_name" "$CONFIG_FILE" 2>/dev/null)
  LOCAL_PATH=$(jq -r ".files[$i].local_path" "$CONFIG_FILE" 2>/dev/null)
  REPO_FILE_PATH=$(jq -r ".files[$i].repo_file_path" "$CONFIG_FILE" 2>/dev/null)
  PRIOR_STATUS=$(jq -r ".files[$i].sync_status // \"\"" "$CONFIG_FILE" 2>/dev/null)
  LAST_SYNC_RAW=$(jq -r ".files[$i].last_sync_at // empty" "$CONFIG_FILE" 2>/dev/null)
  set -e

  NOW_ISO=$(file_sync_now_iso)
  NOW_E=$(file_sync_now_epoch)

  if [[ -z "$REPO_NAME" ]] || [[ "$REPO_NAME" == "null" ]]; then
    echo -e "${RED}✗ Entry $i: Invalid repo_name in config${NC}"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" '{i: $idx, last_check_at: $now, sync_status: "error_invalid_repo"}')"
    continue
  fi

  if [[ -n "$REPO_FILTER" ]] && [[ "$REPO_NAME" != "$REPO_FILTER" ]]; then
    continue
  fi

  if ! filesync_file_matches_fragment "$FILE_FRAGMENT" "$LOCAL_PATH" "$REPO_FILE_PATH"; then
    continue
  fi

  if [[ -z "$LOCAL_PATH" ]] || [[ "$LOCAL_PATH" == "null" ]]; then
    echo -e "${RED}✗ Entry $i: Invalid local_path in config${NC}"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" '{i: $idx, last_check_at: $now, sync_status: "error_invalid_local_path"}')"
    continue
  fi

  if [[ -z "$REPO_FILE_PATH" ]] || [[ "$REPO_FILE_PATH" == "null" ]]; then
    echo -e "${RED}✗ $LOCAL_PATH: Invalid repo_file_path in config${NC}"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" '{i: $idx, last_check_at: $now, sync_status: "error_invalid_repo_path"}')"
    continue
  fi

  REPO_ROOT=""
  if ! REPO_ROOT=$(filesync_get_repo_dir "$REPO_NAME"); then
    echo -e "${RED}✗ $LOCAL_PATH: Could not resolve repo $REPO_NAME${NC}"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc --argjson idx "$i" --arg now "$NOW_ISO" '{i: $idx, last_check_at: $now, sync_status: "error_repo_unavailable"}')"
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
      '{
        i: $idx,
        last_check_at: $now,
        sync_status: "detached",
        repo_file_modified_at: (if $rs == "" then null else $rs end),
        local_file_modified_at: (if $ls == "" then null else $ls end)
      }')"
    printf '%b[%s]%b %s %s: detached (mapping inactive)\n' "$(col_st detached)" "detached" "$(rst)" "${WHITE}" "$LOCAL_PATH"
    continue
  fi

  if [[ ! -f "$FULL_MASTER_PATH" ]]; then
    echo -e "$(col_st error_missing_master)${RED}✗${NC} ${WHITE}$LOCAL_PATH: Source not found in $REPO_NAME ($REPO_FILE_PATH)${NC}"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc \
      --argjson idx "$i" \
      --arg now "$NOW_ISO" \
      --arg ls "${LOCAL_ISO:-}" \
      '{
        i: $idx,
        last_check_at: $now,
        sync_status: "error_missing_master",
        repo_file_modified_at: null,
        local_file_modified_at: (if $ls == "" then null else $ls end)
      }')"
    continue
  fi

  if [[ ! -f "$FULL_LOCAL_PATH" ]]; then
    echo -e "$(col_st error_missing_local)${RED}✗${NC} ${WHITE}$LOCAL_PATH: Local file not found${NC}"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc \
      --argjson idx "$i" \
      --arg now "$NOW_ISO" \
      --arg rs "${REPO_ISO:-}" \
      '{
        i: $idx,
        last_check_at: $now,
        sync_status: "error_missing_local",
        repo_file_modified_at: (if $rs == "" then null else $rs end),
        local_file_modified_at: null
      }')"
    continue
  fi

  if ! has_clone_file_sync_marker "$FULL_LOCAL_PATH" 2>/dev/null; then
    echo -e "$(col_st error_no_clone_marker)${YELLOW}⚠${NC} ${WHITE}$LOCAL_PATH: Missing filesync:sync kind=clone marker${NC}"
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
    append_patch "$(jq -nc \
      --argjson idx "$i" \
      --arg now "$NOW_ISO" \
      --arg rs "${REPO_ISO:-}" \
      --arg ls "${LOCAL_ISO:-}" \
      '{
        i: $idx,
        last_check_at: $now,
        sync_status: "error_no_clone_marker",
        repo_file_modified_at: (if $rs == "" then null else $rs end),
        local_file_modified_at: (if $ls == "" then null else $ls end)
      }')"
    continue
  fi

  EXPECTED_TMP=$(mktemp)
  render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$EXPECTED_TMP"
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

  append_patch "$(jq -nc \
    --argjson idx "$i" \
    --arg now "$NOW_ISO" \
    --arg rs "${REPO_ISO:-}" \
    --arg ls "${LOCAL_ISO:-}" \
    --arg st "$STATUS" \
    '{
      i: $idx,
      last_check_at: $now,
      sync_status: $st,
      repo_file_modified_at: (if $rs == "" then null else $rs end),
      local_file_modified_at: (if $ls == "" then null else $ls end)
    }')"

  if [[ "$STATUS" == "conflict" ]] || [[ "$STATUS" =~ ^error_ ]]; then
    BLOCKING_ISSUES=$((BLOCKING_ISSUES + 1))
  fi

  printf '%b[%s]%b %s%s\n' "$(col_st "$STATUS")" "$STATUS" "$(rst)" "${WHITE}" "$LOCAL_PATH"
done

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

echo ""
if [[ -n "$FILE_FRAGMENT" ]] && [[ "$CHECKED" -eq 0 ]]; then
  echo -e "${YELLOW}No file rows matched --file=${FILE_FRAGMENT}${NC} (and repo filter if any)."
fi
if [[ $BLOCKING_ISSUES -gt 0 ]]; then
  echo -e "${RED}Check completed with $BLOCKING_ISSUES blocking issue(s).${NC} ${WHITE}Rows updated: $CHECKED${NC}"
  exit 1
fi

echo -e "${GREEN}✓${NC} ${WHITE}Check OK ($CHECKED files updated).${NC}"
exit 0
