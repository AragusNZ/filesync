#!/usr/bin/env bash
# CLI: filesync new repo — interactive append to global repos.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync new repo
Also: n -r

Interactively add one repository to the shared catalog (repos.json): name, checkout path, URL,
branch, stable id.

When to use it:
  Run from any directory; defaults come from git when cwd is inside a work tree and from cwd
  otherwise. You are prompted for the checkout path (relative to the repo path root — usually your
  home — or an absolute directory); press Enter to accept the default derived from cwd/git.
  You do not need a project .filesync/ folder.
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/git-repo-hints.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/global-repo-interactive.sh"
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
path_default="$(filesync_path_for_repos_json "$rroot" "$def_checkout")"
if [[ -z "$path_default" ]]; then
  echo -e "${RED}filesync: could not derive default checkout path (repo_path_root=${rroot}, checkout=${def_checkout})${NC}" >&2
  exit 1
fi

echo -e "${BOLD}${WHITE}Add a repo to global ${FILESYNC_GLOBAL_REPOS_NAME}${NC}" >&2
filesync_global_repo_print_path_banner "$rroot" "$def_checkout" "$path_default"

read -rp "Repo nickname (used for targeting): " name
[[ -n "$name" ]] || { echo -e "${RED}Name is required.${NC}" >&2; exit 1; }

if jq -e --arg n "$name" 'any(.name == $n)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$name' already exists in global repos.${NC}" >&2
  exit 1
fi
if [[ -f "$coll" ]] && filesync_collections_name_taken "$coll" "$name"; then
  echo -e "${RED}Error: '$name' is already a collection name; repo names must be distinct from collection names.${NC}" >&2
  exit 1
fi

path="$(filesync_global_repo_prompt_stored_path "$rroot" "$def_checkout" "$path_default")" || {
  echo -e "${RED}filesync: checkout path must be an existing directory (relative to repo path root or absolute).${NC}" >&2
  exit 1
}

read -rp "URL (e.g. https://github.com/org/repo): " url

read -rp "Branch (default: main): " branch
branch="${branch:-main}"

NEW_ENTRY="$(filesync_global_repo_row_json "$name" "$url" "$path" "$branch" "$rroot")" || {
  echo -e "${RED}filesync: could not resolve checkout directory for path=${path}${NC}" >&2
  exit 1
}

filesync_global_repo_append_row_locked "$repos" "$NEW_ENTRY"

echo "" >&2
echo -e "${GREEN}Added repo:${NC} name=$name url=$url path=$path branch=$branch" >&2
