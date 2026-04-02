#!/usr/bin/env bash
# CLI: filesync edit-collection — rename collection or add/remove repo members.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync edit-collection <name> [options]
Alias: ecol

At least one option is required.

Options:
  --rename=new_name     Rename the collection (must not match a repo or other collection)
  --add-repo=name       Add a repo that exists in repos.json
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
filesync_command_init_lite "${BASH_SOURCE[0]}"

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
      echo -e "${RED}Unknown option: $1${NC}" >&2
      exit 1
      ;;
    *)
      if [[ -z "$CUR" ]]; then
        CUR="$1"
      else
        echo -e "${RED}Unexpected argument: $1${NC}" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$CUR" ]]; then
  echo -e "${RED}Usage: filesync edit-collection <name> [--rename=] [--add-repo=] [--remove-repo=]${NC}" >&2
  exit 1
fi

if [[ -z "$RENAME" ]] && [[ -z "$ADD_REPO" ]] && [[ -z "$RM_REPO" ]]; then
  echo -e "${RED}Error: specify at least one of --rename, --add-repo, --remove-repo${NC}" >&2
  exit 1
fi

repos="$FILESYNC_DIR/$FILESYNC_REPOS_NAME"
coll="$FILESYNC_DIR/$FILESYNC_COLLECTIONS_NAME"

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
