#!/usr/bin/env bash
# Sync from master repos into project (updates .filesync/files.json rows).
# Usage: sync.sh [--repo=name] [--file=path_fragment] [--dry-run] [--force] [--all] [--include-status=a,b] [--include-detached]
# Path fragment: substring match on local_path or repo_file_path (after optional --repo filter).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

REPO_FILTER=""
FILE_FRAGMENT=""
DRY_RUN=false
FORCE=false
SYNC_ALL=false
INCLUDE_STATUS_EXTRA=""
INCLUDE_DETACHED=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --all) SYNC_ALL=true; shift ;;
    --include-status=*) INCLUDE_STATUS_EXTRA="${1#*=}"; shift ;;
    --include-detached) INCLUDE_DETACHED=true; shift ;;
    --repo=*)
      REPO_FILTER="${1#*=}"
      shift
      ;;
    --file=*)
      FILE_FRAGMENT="${1#*=}"
      shift
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

sync_entry_allowed() {
  local status="${1:-}"
  [[ "$status" == "null" ]] && status=""
  if [[ "$status" == "detached" ]]; then
    [[ "$INCLUDE_DETACHED" == true ]] && return 0
    return 1
  fi
  if [[ "$SYNC_ALL" == true ]]; then
    return 0
  fi
  if [[ -z "$status" ]] || [[ "$status" == "sync_required" ]]; then
    return 0
  fi
  if [[ -n "$INCLUDE_STATUS_EXTRA" ]]; then
    local tok
    IFS=',' read -ra _extra <<< "$INCLUDE_STATUS_EXTRA"
    for tok in "${_extra[@]}"; do
      tok="${tok//[[:space:]]/}"
      [[ "$tok" == "$status" ]] && return 0
    done
  fi
  return 1
}

# shellcheck disable=SC2034
declare -A FILESYNC_REPO_DIR_CACHE
declare -a FILESYNC_CLONED_TEMP_DIRS

cleanup_sync_exit() {
  # shellcheck disable=SC2317
  rm -f "${FILESYNC_STATE_FILE:-}"
  # shellcheck disable=SC2317
  rm -rf "${FILESYNC_CLONED_TEMP_DIRS[@]:-}"
}
trap cleanup_sync_exit EXIT

if ! jq -e '.file_sync_enabled == true' "$CONFIG_FILE" &>/dev/null; then
  echo -e "${YELLOW}filesync is disabled. Run 'filesync enable' to enable.${NC}"
  exit 0
fi

if ! jq -e '.repos | length > 0' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo -e "${RED}Error: Config must have at least one entry in repos${NC}"
  exit 1
fi

SYNCED=0
ALREADY_SYNCED=0
FAILED=0
SKIPPED=0
STATUS_SKIPPED=0

FILE_PATH_MATCHES=0

echo -e "${CYAN}Syncing files from repo(s)...${NC}"
[[ -n "$REPO_FILTER" ]] && echo -e "${CYAN}Filter: --repo=$REPO_FILTER${NC}"
[[ -n "$FILE_FRAGMENT" ]] && echo -e "${CYAN}Filter: --file= substring on local_path or repo_file_path: ${FILE_FRAGMENT}${NC}"
if [[ "$SYNC_ALL" == true ]]; then
  echo -e "${CYAN}Mode: --all (all coupled statuses)${NC}"
elif [[ -n "$INCLUDE_STATUS_EXTRA" ]]; then
  echo -e "${CYAN}Extra statuses: $INCLUDE_STATUS_EXTRA${NC}"
else
  echo -e "${CYAN}Mode: unset or sync_required only (use --all or --include-status=...)${NC}"
fi
echo ""

FILES_COUNT=$(jq '.files | length' "$CONFIG_FILE")

for ((i=0; i<FILES_COUNT; i++)); do
  set +e
  REPO_NAME=$(jq -r ".files[$i].repo_name" "$CONFIG_FILE" 2>/dev/null)
  LOCAL_PATH=$(jq -r ".files[$i].local_path" "$CONFIG_FILE" 2>/dev/null)
  REPO_FILE_PATH=$(jq -r ".files[$i].repo_file_path" "$CONFIG_FILE" 2>/dev/null)
  ROW_STATUS=$(jq -r ".files[$i].sync_status // \"\"" "$CONFIG_FILE" 2>/dev/null)
  set -e

  if [[ -z "$REPO_NAME" ]] || [[ "$REPO_NAME" == "null" ]]; then
    echo -e "${RED}✗ Entry $i: Invalid repo_name in config${NC}"
    FAILED=$((FAILED + 1))
    continue
  fi

  if [[ -n "$REPO_FILTER" ]] && [[ "$REPO_NAME" != "$REPO_FILTER" ]]; then
    continue
  fi

  if ! filesync_file_matches_fragment "$FILE_FRAGMENT" "$LOCAL_PATH" "$REPO_FILE_PATH"; then
    continue
  fi
  FILE_PATH_MATCHES=$((FILE_PATH_MATCHES + 1))

  if [[ -z "$LOCAL_PATH" ]] || [[ "$LOCAL_PATH" == "null" ]]; then
    echo -e "${RED}✗ Entry $i: Invalid local_path in config${NC}"
    FAILED=$((FAILED + 1))
    continue
  fi

  if [[ -z "$REPO_FILE_PATH" ]] || [[ "$REPO_FILE_PATH" == "null" ]]; then
    echo -e "${RED}✗ $LOCAL_PATH: Invalid repo_file_path in config${NC}"
    FAILED=$((FAILED + 1))
    continue
  fi

  if ! sync_entry_allowed "$ROW_STATUS"; then
    echo -e "${YELLOW}⊘ $LOCAL_PATH: Skipped (sync_status=${ROW_STATUS:-unset}, not selected)${NC}"
    STATUS_SKIPPED=$((STATUS_SKIPPED + 1))
    continue
  fi

  REPO_ROOT=""
  REPO_ROOT=$(filesync_get_repo_dir "$REPO_NAME") || { FAILED=$((FAILED + 1)); continue; }

  FULL_LOCAL_PATH="$PROJECT_ROOT/$LOCAL_PATH"
  FULL_MASTER_PATH="$REPO_ROOT/$REPO_FILE_PATH"

  if [[ ! -f "$FULL_MASTER_PATH" ]]; then
    echo -e "${RED}✗ $LOCAL_PATH: Source file not found in $REPO_NAME ($REPO_FILE_PATH)${NC}"
    FAILED=$((FAILED + 1))
    continue
  fi

  if ! has_master_file_sync_marker "$FULL_MASTER_PATH" 2>/dev/null; then
    echo -e "${YELLOW}⚠ $LOCAL_PATH: Skipped (source file missing filesync kind=master marker)${NC}"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [[ -f "$FULL_LOCAL_PATH" ]]; then
    if ! has_clone_file_sync_marker "$FULL_LOCAL_PATH" 2>/dev/null; then
      if [[ "$FORCE" != true ]]; then
        echo -e "${YELLOW}⚠ $LOCAL_PATH: Skipped (missing filesync kind=clone marker, use --force)${NC}"
        SKIPPED=$((SKIPPED + 1))
        continue
      fi
    fi
  fi

  if [[ -f "$FULL_LOCAL_PATH" ]]; then
    EXPECTED_TMP=$(mktemp)
    if ! render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$EXPECTED_TMP"; then
      rm -f "$EXPECTED_TMP"
      filesync_error "${LOCAL_PATH}: could not render clone from master ${REPO_NAME}/${REPO_FILE_PATH} (master file missing or unparsable filesync marker)"
      FAILED=$((FAILED + 1))
      continue
    fi
    set +e
    diff -q "$EXPECTED_TMP" "$FULL_LOCAL_PATH" >/dev/null 2>&1
    DIFF_RESULT=$?
    set -e
    rm -f "$EXPECTED_TMP"
    if [[ $DIFF_RESULT -eq 0 ]]; then
      echo -e "${GREEN}✓${NC} ${WHITE}$LOCAL_PATH: Already in sync${NC}"
      ALREADY_SYNCED=$((ALREADY_SYNCED + 1))
      if [[ "$DRY_RUN" != true ]]; then
        filesync_write_file_row "$FILESYNC_FILES_FILE" "$PROJECT_ROOT" "$LOCAL_PATH" "$FULL_MASTER_PATH" "synced"
      fi
      continue
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}→ $LOCAL_PATH: Would sync from $REPO_NAME/$REPO_FILE_PATH${NC}"
  else
    mkdir -p "$(dirname "$FULL_LOCAL_PATH")"
    if ! render_clone_from_master_file "$FULL_MASTER_PATH" "$REPO_FILE_PATH" "$REPO_NAME" "$FULL_LOCAL_PATH"; then
      filesync_error "${LOCAL_PATH}: could not render clone from master ${REPO_NAME}/${REPO_FILE_PATH} (master file missing or unparsable filesync marker)"
      FAILED=$((FAILED + 1))
      continue
    fi
    echo -e "${GREEN}✓ $LOCAL_PATH: Synced${NC}"
    filesync_write_file_row "$FILESYNC_FILES_FILE" "$PROJECT_ROOT" "$LOCAL_PATH" "$FULL_MASTER_PATH" "synced"
  fi
  SYNCED=$((SYNCED + 1))
done

if [[ -n "$FILE_FRAGMENT" ]] && [[ "$FILE_PATH_MATCHES" -eq 0 ]]; then
  echo ""
  echo -e "${YELLOW}No file rows matched --file=${FILE_FRAGMENT}${NC} (and repo filter if any)."
fi

if [[ $FAILED -gt 0 ]]; then
  echo ""
  echo -e "${RED}Failed: $FAILED${NC} ${WHITE}| Synced: $SYNCED | Already in sync: $ALREADY_SYNCED | Skipped: $SKIPPED | Status-filtered: $STATUS_SKIPPED${NC}"
  filesync_error "exiting with status 1 because $FAILED file(s) failed to sync."
  exit 1
elif [[ "$DRY_RUN" == true ]]; then
  echo ""
  if [[ $SYNCED -gt 0 ]]; then
    echo -e "${YELLOW}Dry run: $SYNCED files would be synced${NC}"
  else
    echo -e "${GREEN}✓${NC} ${WHITE}Nothing to sync ($ALREADY_SYNCED already in sync, $STATUS_SKIPPED status-skipped)${NC}"
  fi
else
  echo ""
  if [[ $SYNCED -gt 0 ]]; then
    echo -e "${GREEN}✓ Success: $SYNCED files synced${NC}"
  else
    echo -e "${GREEN}✓${NC} ${WHITE}Nothing to sync ($ALREADY_SYNCED already in sync, $STATUS_SKIPPED status-skipped)${NC}"
  fi
fi

exit 0
