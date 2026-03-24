#!/usr/bin/env bash
# Resolve repo checkout paths from config path_mode.

# Args: project_root path_from_json path_mode
# Echo absolute directory path or empty if not resolvable.
filesync_resolve_repo_path() {
  local project_root="$1"
  local rel_or_abs="$2"
  local mode="${3:-relative}"

  if [[ -z "$rel_or_abs" || "$rel_or_abs" == "null" ]]; then
    echo ""
    return 1
  fi

  if [[ "$mode" == "absolute" ]]; then
    if [[ -d "$rel_or_abs" ]]; then
      (cd "$rel_or_abs" && pwd) || echo ""
    else
      echo ""
      return 1
    fi
    return 0
  fi

  # relative to project root
  (cd "$project_root" && cd "$rel_or_abs" 2>/dev/null && pwd) || echo ""
}
