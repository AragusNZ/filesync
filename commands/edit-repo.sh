#!/usr/bin/env bash
# CLI: filesync edit-repo — update repos.json; optional rename updates repo_name in files.json and repo= in local markers.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

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
files="$FILESYNC_FILES_FILE"

if ! jq -e --arg c "$REPO_CURRENT" 'any(.name == $c)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$REPO_CURRENT' not found in repos.${NC}" >&2
  exit 1
fi

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  if jq -e --arg n "$RENAME" 'any(.name == $n)' "$repos" &>/dev/null; then
    echo -e "${RED}Error: Repo name '$RENAME' already exists.${NC}" >&2
    exit 1
  fi
fi

tmp_repos="$(mktemp)"
tmp_files="$(mktemp)"
cleanup_er() {
  # shellcheck disable=SC2317
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

if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  while IFS= read -r _lp || [[ -n "${_lp:-}" ]]; do
    [[ -z "$_lp" || "$_lp" == "null" ]] && continue
    _full="${PROJECT_ROOT}/${_lp}"
    filesync_marker_rename_repo_in_file "$_full" "$REPO_CURRENT" "$RENAME" || true
  done < <(jq -r --arg c "$REPO_CURRENT" '.[] | select(.repo_name == $c) | .local_path' "$files")
fi

mv "$tmp_repos" "$repos"
mv "$tmp_files" "$files"

echo -e "${GREEN}Updated repo${NC} ${WHITE}$REPO_CURRENT${NC}:" >&2
if [[ -n "$RENAME" ]] && [[ "$RENAME" != "$REPO_CURRENT" ]]; then
  echo "  Renamed to: $RENAME (files.json repo_name and local clone/detached markers updated)" >&2
fi
if [[ -n "$PATH_NEW" ]]; then echo "  path: $PATH_NEW" >&2; fi
if [[ -n "$URL_NEW" ]]; then echo "  url: $URL_NEW" >&2; fi
if [[ -n "$BRANCH_NEW" ]]; then echo "  branch: $BRANCH_NEW" >&2; fi
exit 0
