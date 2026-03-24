#!/usr/bin/env bash
# Update a repo in repos.json; optional rename updates repo_name in every files.json row.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_CURRENT=""
RENAME=""
PATH_NEW=""
URL_NEW=""
BRANCH_NEW=""

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
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync repo-edit <repo_name> [--rename=new] [--path=...] [--url=...] [--branch=...]" >&2
      exit 1
      ;;
    *)
      if [[ -z "$REPO_CURRENT" ]]; then
        REPO_CURRENT="$1"
      else
        echo -e "${RED}Unexpected argument: $1${NC}" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$REPO_CURRENT" ]]; then
  echo -e "${RED}Usage: filesync repo-edit <repo_name> [--rename=new] [--path=...] [--url=...] [--branch=...]${NC}"
  echo "At least one of --rename, --path, --url, or --branch is required."
  exit 1
fi

if [[ -z "$RENAME" ]] && [[ -z "$PATH_NEW" ]] && [[ -z "$URL_NEW" ]] && [[ -z "$BRANCH_NEW" ]]; then
  echo -e "${RED}Error: specify at least one of --rename, --path, --url, --branch${NC}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo -e "${RED}jq is required.${NC}"
  exit 1
fi

repos="$FILESYNC_REPOS_FILE"
files="$FILESYNC_FILES_FILE"

if ! jq -e --arg c "$REPO_CURRENT" 'any(.name == $c)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$REPO_CURRENT' not found in repos.${NC}"
  exit 1
fi

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  if jq -e --arg n "$RENAME" 'any(.name == $n)' "$repos" &>/dev/null; then
    echo -e "${RED}Error: Repo name '$RENAME' already exists.${NC}"
    exit 1
  fi
fi

tmp_repos="$(mktemp)"
tmp_files="$(mktemp)"
cleanup_er() {
  rm -f "$tmp_repos" "$tmp_files"
}
trap 'cleanup_er; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

jq --arg c "$REPO_CURRENT" \
  --arg newname "$RENAME" \
  --arg p "$PATH_NEW" \
  --arg u "$URL_NEW" \
  --arg b "$BRANCH_NEW" \
  'map(
    if .name == $c then
      .name = (if $newname != "" then $newname else .name end)
      | .path = (if $p != "" then $p else .path end)
      | .url = (if $u != "" then $u else .url end)
      | .branch = (if $b != "" then $b else .branch end)
    else . end
  )' "$repos" > "$tmp_repos"

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  jq --arg c "$REPO_CURRENT" --arg n "$RENAME" \
    'map(if .repo_name == $c then .repo_name = $n else . end)' "$files" > "$tmp_files"
else
  cp "$files" "$tmp_files"
fi

mv "$tmp_repos" "$repos"
mv "$tmp_files" "$files"

echo -e "${GREEN}Updated repo${NC} ${CYAN}$REPO_CURRENT${NC}:"
if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  echo "  Renamed to: $RENAME (all matching files.json repo_name values updated)"
fi
[[ -n "$PATH_NEW" ]] && echo "  path: $PATH_NEW"
[[ -n "$URL_NEW" ]] && echo "  url: $URL_NEW"
[[ -n "$BRANCH_NEW" ]] && echo "  branch: $BRANCH_NEW"
