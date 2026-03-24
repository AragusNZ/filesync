#!/usr/bin/env bash
# Interactive: append a repo to .filesync/repos.json.

set -euo pipefail

_PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$_PKG/lib/resolve.sh"
filesync_resolve_or_exit

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

repos="$FILESYNC_DIR/$FILESYNC_REPOS_NAME"
if [[ ! -f "$repos" ]]; then
  echo -e "${RED}Missing $repos — create it (JSON array of repos).${NC}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo -e "${RED}jq is required.${NC}"
  exit 1
fi

echo -e "${CYAN}Add a repo to .filesync/$FILESYNC_REPOS_NAME${NC}"
echo ""

read -rp "Repo name (e.g. greenlit-api): " name
[[ -n "$name" ]] || { echo -e "${RED}Name is required.${NC}"; exit 1; }

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

echo ""
echo -e "${GREEN}Added repo:${NC} name=$name url=$url path=$path branch=$branch"
