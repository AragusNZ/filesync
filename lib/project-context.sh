#!/usr/bin/env bash
# Helpers for working with multiple initialized filesync projects.
#
# Notes:
# - A "project root" is the directory containing a ".filesync/" folder.
# - Repo checkout paths in global repos.json are relative to repo_path_root (system.json).

_LIB_PC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_PC}/data-names.sh"
# shellcheck source=/dev/null
source "${_LIB_PC}/paths.sh"

filesync_project_filesync_dir() {
  local project_root="$1"
  echo "$project_root/.filesync"
}

# Args: repo_path_root global_repos_json_path repo_name
# Echo resolved absolute repo checkout dir, or empty.
filesync_project_resolve_repo_dir() {
  local repo_path_root="$1"
  local repos_json="$2"
  local repo_name="$3"
  local repo_path
  repo_path=$(jq -r --arg n "$repo_name" '.[] | select(.name == $n) | .path // ""' "$repos_json" | head -1)
  filesync_resolve_repo_checkout_dir "$repo_path_root" "$repo_path"
}

# Args: repo_path_root global_repos_json_path also_repo_name
# Echo sibling project root (absolute), or empty.
filesync_resolve_also_project_root() {
  local repo_path_root="$1"
  local repos_json="$2"
  local also_repo="$3"
  local also_path
  also_path=$(jq -r --arg n "$also_repo" '.[] | select(.name == $n) | .path // ""' "$repos_json" | head -1)
  filesync_resolve_repo_checkout_dir "$repo_path_root" "$also_path"
}
