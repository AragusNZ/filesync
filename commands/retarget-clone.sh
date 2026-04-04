#!/usr/bin/env bash
# Retarget one tracked clone row to a new repo_file_path after git mv on the master.
# Usage: retarget-clone.sh <local_clone> <new_repo_file_path> [--move|--mv]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync retarget clone <local_clone> <new_repo_file_path> [--move|--mv]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: retarget -c

After git mv on the master, update one clone row in this project only. The first path must be a
tracked clone (same resolution as filesync info file). The second path is repo-relative and must
exist in the checkout as the moved master (kind=master).

Arguments:

  <local_clone>           Clone path in this project.
  <new_repo_file_path>    New path to the master inside the repo.

What happens next:

  Default (no --move): row is marked so sync can refresh content; the local file is not moved yet.
  --move / --mv: move the local file to the new path and update the stored local_path.

For every project that shares the same master, use:
  filesync retarget master …
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
  echo -e "${RED}Missing <local_clone> or <new_repo_file_path>${NC}" >&2
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

filesync_retarget_new_rfp_must_be_relative "$NEW_RFP" || exit 1

if ! filesync_file_rel_gather_from_path "$LOCAL_ARG"; then
  exit 1
fi

if [[ "$FILESYNC_REL_MODE" != "clone" ]]; then
  echo -e "${RED}This path is not a tracked clone in the current project.${NC}" >&2
  echo -e "${YELLOW}To retarget every mapping for the canonical master across projects, use:${NC} filesync retarget master <master_path> <new_repo_file_path>${NC}" >&2
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

# shellcheck disable=SC2153
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

filesync_retarget_apply_jq_clone "$fj" "$lp" "$NEW_RFP" "$DO_MOVE" "$NOW_ISO"

echo -e "${GREEN}Retargeted clone:${NC} repo_file_path ${FILESYNC_REL_RFP} -> $NEW_RFP (project $PROJECT_ROOT)" >&2
