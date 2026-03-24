#!/usr/bin/env bash
# Resolve local clone directories for repo names (uses CONFIG_FILE, PROJECT_ROOT, PATH_MODE).

# Caller must: declare -A FILESYNC_REPO_DIR_CACHE; declare -a FILESYNC_CLONED_TEMP_DIRS
# Optional: filesync_cleanup_clones on EXIT

filesync_get_repo_info() {
  local name="$1"
  jq -r --arg n "$name" '
    .repos[] | select(.name == $n) | "\(.path)|\(.url // "")|\(.branch // "main")"
  ' "$CONFIG_FILE" | head -1
}

filesync_get_repo_dir() {
  local repo_name="$1"
  if [[ -n "${FILESYNC_REPO_DIR_CACHE[$repo_name]:-}" ]]; then
    echo "${FILESYNC_REPO_DIR_CACHE[$repo_name]}"
    return
  fi
  local info
  info=$(filesync_get_repo_info "$repo_name")
  if [[ -z "$info" ]]; then
    echo -e "${RED:-}Error: Repo '$repo_name' not found in config .repos${NC:-}" >&2
    return 1
  fi
  local repo_path url branch
  IFS='|' read -r repo_path url branch <<< "$info"
  if [[ -n "$repo_path" ]] && [[ "$repo_path" != "null" ]]; then
    local abs_path
    abs_path=$(filesync_resolve_repo_path "$PROJECT_ROOT" "$repo_path" "${PATH_MODE:-relative}")
    if [[ -n "$abs_path" ]] && [[ -d "$abs_path" ]]; then
      FILESYNC_REPO_DIR_CACHE[$repo_name]="$abs_path"
      echo "$abs_path"
      return
    fi
  fi
  if [[ -z "$url" ]] || [[ "$url" == "null" ]]; then
    echo -e "${RED:-}Error: Repo '$repo_name' has no valid path or url in config${NC:-}" >&2
    return 1
  fi
  local tmp_dir
  tmp_dir=$(mktemp -d)
  FILESYNC_CLONED_TEMP_DIRS+=("$tmp_dir")
  echo -e "${YELLOW:-}Cloning $repo_name from $url...${NC:-}" >&2
  git clone --depth 1 --branch "$branch" "$url" "$tmp_dir/$repo_name" || {
    echo -e "${RED:-}Error: Failed to clone $repo_name${NC:-}" >&2
    return 1
  }
  FILESYNC_REPO_DIR_CACHE[$repo_name]="$tmp_dir/$repo_name"
  echo "$tmp_dir/$repo_name"
}
