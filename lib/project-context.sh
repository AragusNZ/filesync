#!/usr/bin/env bash
# Helpers for working with multiple initialized filesync projects.
#
# Notes:
# - A "project root" is the directory containing a ".filesync/" folder.
# - Repo checkout paths in repos.json are interpreted via that project's path_mode.

filesync_project_filesync_dir() {
  local project_root="$1"
  echo "$project_root/.filesync"
}

filesync_project_config_path() {
  local project_root="$1"
  echo "$(filesync_project_filesync_dir "$project_root")/config.json"
}

filesync_project_repos_path() {
  local project_root="$1"
  echo "$(filesync_project_filesync_dir "$project_root")/repos.json"
}

filesync_project_files_path() {
  local project_root="$1"
  echo "$(filesync_project_filesync_dir "$project_root")/files.json"
}

filesync_project_read_path_mode() {
  local project_root="$1"
  local cfg
  cfg="$(filesync_project_config_path "$project_root")"
  if [[ -f "$cfg" ]]; then
    jq -r '.path_mode // "relative"' "$cfg"
  else
    echo "relative"
  fi
}

# Args: project_root repo_name
# Echo resolved absolute repo checkout dir, or empty.
filesync_project_resolve_repo_dir() {
  local project_root="$1"
  local repo_name="$2"
  local repos_json mode repo_path

  repos_json="$(filesync_project_repos_path "$project_root")"
  mode="$(filesync_project_read_path_mode "$project_root")"
  repo_path=$(jq -r --arg n "$repo_name" '.[] | select(.name == $n) | .path // ""' "$repos_json" | head -1)
  filesync_resolve_repo_path "$project_root" "$repo_path" "$mode"
}

# Args: current_project_root current_repos_json also_repo_name current_path_mode
# Echo sibling project root (absolute), or empty.
filesync_resolve_also_project_root() {
  local project_root="$1"
  local current_repos_json="$2"
  local also_repo="$3"
  local current_mode="${4:-relative}"

  local also_path
  also_path=$(jq -r --arg n "$also_repo" '.[] | select(.name == $n) | .path // ""' "$current_repos_json" | head -1)
  filesync_resolve_repo_path "$project_root" "$also_path" "$current_mode"
}

