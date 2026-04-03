#!/usr/bin/env bash
# CLI: filesync add-repo — interactive append to global repos.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync add-repo
Alias: ar

Interactively append a new repo entry to the global repos.json (name, URL, branch, stable id).
The checkout path is stored relative to your home directory when possible. Run from the repo
checkout you are registering; does not require a project .filesync.
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/paths.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/git-repo-hints.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/repo-id.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/fs-lock.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

repos="$FILESYNC_REPOS_FILE"
coll="$FILESYNC_COLLECTIONS_FILE"

rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"
if [[ -z "$rroot" || "$rroot" == "null" ]]; then
  echo -e "${RED}filesync: could not resolve path anchor (HOME)${NC}" >&2
  exit 1
fi
filesync_git_collect_hints "$(pwd -P)"
def_checkout="${FILESYNC_GIT_HINT_TOP:-$(pwd -P)}"
path="$(filesync_path_for_repos_json "$rroot" "$def_checkout")"
if [[ -z "$path" ]]; then
  echo -e "${RED}filesync: could not derive checkout path under repo_path_root (repo_path_root=${rroot}, checkout=${def_checkout})${NC}" >&2
  exit 1
fi

echo -e "${BOLD}${WHITE}Add a repo to global ${FILESYNC_GLOBAL_REPOS_NAME}${NC}" >&2
echo -e "${GRAY}Checkout path (relative to home when possible): ${path}${NC}" >&2
echo "" >&2

read -rp "Repo name (e.g. greenlit-api): " name
[[ -n "$name" ]] || { echo -e "${RED}Name is required.${NC}" >&2; exit 1; }

if jq -e --arg n "$name" 'any(.name == $n)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$name' already exists in global repos.${NC}" >&2
  exit 1
fi
if [[ -f "$coll" ]] && filesync_collections_name_taken "$coll" "$name"; then
  echo -e "${RED}Error: '$name' is already a collection name; repo names must be distinct from collection names.${NC}" >&2
  exit 1
fi

read -rp "URL (e.g. https://github.com/org/repo): " url

read -rp "Branch (default: main): " branch
branch="${branch:-main}"

rid="$(filesync_new_repo_id)"
NEW_ENTRY=$(jq -n \
  --arg id "$rid" \
  --arg name "$name" \
  --arg url "$url" \
  --arg path "$path" \
  --arg branch "$branch" \
  '{id: $id, name: $name, url: $url, path: $path, branch: $branch, check_sync_enabled: true, mirror_in_enabled: true}')

filesync_global_lock_acquire
trap 'filesync_global_lock_release' EXIT
jq --argjson entry "$NEW_ENTRY" '. + [$entry]' "$repos" >"${repos}.tmp"
mv "${repos}.tmp" "$repos"
filesync_global_lock_release
trap - EXIT

echo "" >&2
echo -e "${GREEN}Added repo:${NC} name=$name url=$url path=$path branch=$branch" >&2
