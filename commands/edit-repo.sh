#!/usr/bin/env bash
# CLI: filesync edit-repo — update global repos.json (system store only).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync edit-repo <repo_name> [options]
Alias: er

Update a repo entry in the global store (repos.json). Does not read or modify any project
.filesync/files.json or sync markers. At least one of the options below is required.

Options:
  --rename=new_name    Set display name in repos.json (must not match a collection name)
  --path=new_path      Set checkout path
  --url=new_url        Set remote URL
  --branch=name        Change branch

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
      echo "Usage: filesync edit-repo <repo_name> [--rename=new] [--path=...] [--url=...] [--branch=...]" >&2
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
  echo -e "${RED}Usage: filesync edit-repo <repo_name> [--rename=new] [--path=...] [--url=...] [--branch=...]${NC}" >&2
  echo "At least one of --rename, --path, --url, or --branch is required." >&2
  exit 1
fi

if [[ -z "$RENAME" ]] && [[ -z "$PATH_NEW" ]] && [[ -z "$URL_NEW" ]] && [[ -z "$BRANCH_NEW" ]]; then
  echo -e "${RED}Error: specify at least one of --rename, --path, --url, --branch${NC}" >&2
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

tmp_repos="$(mktemp)"
cleanup_er() {
  # shellcheck disable=SC2317
  rm -f "$tmp_repos"
}
trap 'cleanup_er; filesync_global_lock_release 2>/dev/null || true' EXIT

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
  )' "$repos" >"$tmp_repos"

filesync_global_lock_acquire

mv "$tmp_repos" "$repos"

filesync_global_lock_release
trap 'cleanup_er' EXIT

echo -e "${GREEN}Updated repo${NC} ${WHITE}$REPO_CURRENT${NC}:" >&2
if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  echo "  Renamed to: $RENAME (global repos.json only)" >&2
fi
if [[ -n "$PATH_NEW" ]]; then echo "  path: $PATH_NEW" >&2; fi
if [[ -n "$URL_NEW" ]]; then echo "  url: $URL_NEW" >&2; fi
if [[ -n "$BRANCH_NEW" ]]; then echo "  branch: $BRANCH_NEW" >&2; fi
exit 0
