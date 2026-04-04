#!/usr/bin/env bash
# CLI: filesync edit collection — rename collection or add/remove repo members.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync edit collection <name> [options]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: e -col

At least one option is required.

Options:
  --rename=new_name     Rename the collection (must not match a repo or other collection)
  --add-repo=name       Add a repo that exists in global repos.json
  --remove-repo=name    Remove a repo from the collection (ok if already absent)

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/data-names.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

CUR=""
RENAME=""
ADD_REPO=""
RM_REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rename=*)
      RENAME="${1#*=}"
      shift
      ;;
    --add-repo=*)
      ADD_REPO="${1#*=}"
      shift
      ;;
    --remove-repo=*)
      RM_REPO="${1#*=}"
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      if [[ -z "$CUR" ]]; then
        CUR="$1"
      else
        filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$CUR" ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

if [[ -z "$RENAME" ]] && [[ -z "$ADD_REPO" ]] && [[ -z "$RM_REPO" ]]; then
  echo -e "${RED}Error: specify at least one of --rename, --add-repo, --remove-repo${NC}" >&2
  exit 1
fi

repos="$FILESYNC_REPOS_FILE"
coll="$FILESYNC_COLLECTIONS_FILE"

if [[ ! -f "$coll" ]] || ! jq -e --arg n "$CUR" 'any(.name == $n)' "$coll" &>/dev/null; then
  echo -e "${RED}Error: No collection named '$CUR'${NC}" >&2
  exit 1
fi

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$CUR" ]]; then
  if jq -e --arg n "$RENAME" 'any(.name == $n)' "$repos" &>/dev/null; then
    echo -e "${RED}Error: '$RENAME' is already a repo name.${NC}" >&2
    exit 1
  fi
  if jq -e --arg n "$RENAME" 'any(.name == $n)' "$coll" &>/dev/null; then
    echo -e "${RED}Error: Collection '$RENAME' already exists.${NC}" >&2
    exit 1
  fi
fi

if [[ -n "$ADD_REPO" ]]; then
  filesync_collection_add_repo "$coll" "$repos" "$CUR" "$ADD_REPO" || exit 1
fi

if [[ -n "$RM_REPO" ]]; then
  filesync_collection_remove_repo "$coll" "$CUR" "$RM_REPO" || exit 1
fi

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$CUR" ]]; then
  tmp="$(mktemp)"
  jq --arg c "$CUR" --arg n "$RENAME" 'map(if .name == $c then .name = $n else . end)' "$coll" > "$tmp"
  mv "$tmp" "$coll"
fi
if [[ -n "$ADD_REPO" ]]; then
  echo -e "${GREEN}Added repo to collection '${CUR}':${NC} $ADD_REPO" >&2
fi
if [[ -n "$RM_REPO" ]]; then
  echo -e "${GREEN}Removed repo from collection '${CUR}':${NC} $RM_REPO" >&2
fi
if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$CUR" ]]; then
  echo -e "${GREEN}Renamed collection:${NC} $CUR -> $RENAME" >&2
fi
