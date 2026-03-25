#!/usr/bin/env bash
# CLI: filesync add-repo — interactive append to .filesync/repos.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init_lite "${BASH_SOURCE[0]}"

repos="$FILESYNC_DIR/$FILESYNC_REPOS_NAME"
if [[ ! -f "$repos" ]]; then
  echo -e "${RED}Missing $repos — create it (JSON array of repos).${NC}" >&2
  exit 1
fi

echo -e "${BOLD}${WHITE}Add a repo to .filesync/$FILESYNC_REPOS_NAME${NC}" >&2
echo "" >&2

read -rp "Repo name (e.g. greenlit-api): " name
[[ -n "$name" ]] || { echo -e "${RED}Name is required.${NC}" >&2; exit 1; }

read -rp "URL (e.g. https://github.com/org/repo): " url

read -rp "Local path (e.g. ../greenlit-api): " path

read -rp "Branch (default: main): " branch
branch="${branch:-main}"

NEW_ENTRY=$(jq -n \
  --arg name "$name" \
  --arg url "$url" \
  --arg path "$path" \
  --arg branch "$branch" \
  '{name: $name, url: $url, path: $path, branch: $branch}')

jq --argjson entry "$NEW_ENTRY" '. + [$entry]' "$repos" > "${repos}.tmp"
mv "${repos}.tmp" "$repos"

echo "" >&2
echo -e "${GREEN}Added repo:${NC} name=$name url=$url path=$path branch=$branch" >&2
