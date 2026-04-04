#!/usr/bin/env bash
# CLI: filesync edit repo — update global repos.json (system store only).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync edit repo <repo_name> [options]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: e -r

Update one row in the shared repos.json (checkout path, URL, branch, flags). This does not edit
project files.json or file markers. Pass at least one option.

Arguments:

  <repo_name>    Repo name as stored in repos.json.

Options:

  --rename=new_name              New display name (must not match a collection name)
  --path=new_path                Checkout directory for this repo
  --url=new_url                  Remote URL
  --branch=name                  Default branch
  --check-sync=true|false        Run check for this repo during sync
  --mirror-in=true|false         Mirror content in during sync
  --merge-using-git=true|false   Use a git branch/merge in clean trees when syncing (advanced)
  --enable                       Turn check and mirror-in on
  --disable                      Turn check and mirror-in off

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/fs-lock.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

REPO_CURRENT=""
RENAME=""
PATH_NEW=""
URL_NEW=""
BRANCH_NEW=""
CS_SET=0
CS_VAL=false
MI_SET=0
MI_VAL=false
MUG_SET=0
MUG_VAL=false

_bool_from_arg() {
  case "${1,,}" in
    true | 1 | yes) echo true ;;
    false | 0 | no) echo false ;;
    *)
      echo ""
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rename=*)
      RENAME="${1#*=}"
      shift
      ;;
    --path=*)
      PATH_NEW="${1#*=}"
      shift
      ;;
    --url=*)
      URL_NEW="${1#*=}"
      shift
      ;;
    --branch=*)
      BRANCH_NEW="${1#*=}"
      shift
      ;;
    --check-sync=*)
      _b="$(_bool_from_arg "${1#*=}")"
      [[ -n "$_b" ]] || {
        echo -e "${RED}--check-sync must be true or false${NC}" >&2
        exit 1
      }
      CS_SET=1
      [[ "$_b" == true ]] && CS_VAL=true || CS_VAL=false
      shift
      ;;
    --mirror-in=*)
      _b="$(_bool_from_arg "${1#*=}")"
      [[ -n "$_b" ]] || {
        echo -e "${RED}--mirror-in must be true or false${NC}" >&2
        exit 1
      }
      MI_SET=1
      [[ "$_b" == true ]] && MI_VAL=true || MI_VAL=false
      shift
      ;;
    --merge-using-git=*)
      _b="$(_bool_from_arg "${1#*=}")"
      [[ -n "$_b" ]] || {
        echo -e "${RED}--merge-using-git must be true or false${NC}" >&2
        exit 1
      }
      MUG_SET=1
      [[ "$_b" == true ]] && MUG_VAL=true || MUG_VAL=false
      shift
      ;;
    --enable)
      CS_SET=1
      CS_VAL=true
      MI_SET=1
      MI_VAL=true
      shift
      ;;
    --disable)
      CS_SET=1
      CS_VAL=false
      MI_SET=1
      MI_VAL=false
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      if [[ -z "$REPO_CURRENT" ]]; then
        REPO_CURRENT="$1"
      else
        filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$REPO_CURRENT" ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  echo "At least one of --rename, --path, --url, --branch, --check-sync, --mirror-in, --merge-using-git, --enable, or --disable is required." >&2
  exit 1
fi

if [[ -z "$RENAME" ]] && [[ -z "$PATH_NEW" ]] && [[ -z "$URL_NEW" ]] && [[ -z "$BRANCH_NEW" ]] && [[ "$CS_SET" -eq 0 ]] && [[ "$MI_SET" -eq 0 ]] && [[ "$MUG_SET" -eq 0 ]]; then
  echo -e "${RED}Error: specify at least one option${NC}" >&2
  exit 1
fi

repos="$FILESYNC_REPOS_FILE"

if ! jq -e --arg c "$REPO_CURRENT" 'any(.name == $c)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$REPO_CURRENT' not found in repos.${NC}" >&2
  exit 1
fi

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  if jq -e --arg n "$RENAME" 'any(.name == $n)' "$repos" &>/dev/null; then
    echo -e "${RED}Error: Repo name '$RENAME' already exists.${NC}" >&2
    exit 1
  fi
  if [[ -f "$FILESYNC_COLLECTIONS_FILE" ]] && filesync_collections_name_taken "$FILESYNC_COLLECTIONS_FILE" "$RENAME"; then
    echo -e "${RED}Error: '$RENAME' is already a collection name.${NC}" >&2
    exit 1
  fi
fi

# Same directory as repos.json so rename is atomic; global lock serializes writers (see add-repo.sh).
tmp_out="${repos}.tmp"
cleanup_er() {
  # shellcheck disable=SC2317
  rm -f "$tmp_out"
}
trap 'cleanup_er; filesync_global_lock_release 2>/dev/null || true' EXIT

filesync_global_lock_acquire

if ! jq -e --arg c "$REPO_CURRENT" 'any(.name == $c)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$REPO_CURRENT' not found in repos.${NC}" >&2
  exit 1
fi
if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  if jq -e --arg n "$RENAME" 'any(.name == $n)' "$repos" &>/dev/null; then
    echo -e "${RED}Error: Repo name '$RENAME' already exists.${NC}" >&2
    exit 1
  fi
  if [[ -f "$FILESYNC_COLLECTIONS_FILE" ]] && filesync_collections_name_taken "$FILESYNC_COLLECTIONS_FILE" "$RENAME"; then
    echo -e "${RED}Error: '$RENAME' is already a collection name.${NC}" >&2
    exit 1
  fi
fi

jq --arg c "$REPO_CURRENT" \
  --arg newname "$RENAME" \
  --arg p "$PATH_NEW" \
  --arg u "$URL_NEW" \
  --arg b "$BRANCH_NEW" \
  --argjson cs_set "$CS_SET" \
  --argjson cs_val "$CS_VAL" \
  --argjson mi_set "$MI_SET" \
  --argjson mi_val "$MI_VAL" \
  --argjson mug_set "$MUG_SET" \
  --argjson mug_val "$MUG_VAL" \
  'map(
    if .name == $c then
      .name = (if $newname != "" then $newname else .name end)
      | .path = (if $p != "" then $p else .path end)
      | .url = (if $u != "" then $u else .url end)
      | .branch = (if $b != "" then $b else .branch end)
      | .check_sync_enabled = (if $cs_set == 1 then $cs_val else .check_sync_enabled end)
      | .mirror_in_enabled = (if $mi_set == 1 then $mi_val else .mirror_in_enabled end)
      | .merge_using_git = (if $mug_set == 1 then $mug_val else .merge_using_git end)
    else . end
  )' "$repos" >"$tmp_out"

mv "$tmp_out" "$repos"

filesync_global_lock_release
trap - EXIT

echo -e "${GREEN}Updated repo${NC} ${WHITE}$REPO_CURRENT${NC}:" >&2
if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  echo "  Renamed to: $RENAME (global repos.json only)" >&2
fi
if [[ -n "$PATH_NEW" ]]; then echo "  path: $PATH_NEW" >&2; fi
if [[ -n "$URL_NEW" ]]; then echo "  url: $URL_NEW" >&2; fi
if [[ -n "$BRANCH_NEW" ]]; then echo "  branch: $BRANCH_NEW" >&2; fi
if [[ "$CS_SET" -eq 1 ]]; then echo "  check_sync_enabled: $CS_VAL" >&2; fi
if [[ "$MI_SET" -eq 1 ]]; then echo "  mirror_in_enabled: $MI_VAL" >&2; fi
if [[ "$MUG_SET" -eq 1 ]]; then echo "  merge_using_git: $MUG_VAL" >&2; fi
exit 0
