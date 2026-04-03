#!/usr/bin/env bash
# Resolve repo checkout paths from repo_path_root (system-level).

# Args: repo_path_root path_from_json
# Echo absolute directory path or empty if not resolvable.
filesync_resolve_repo_checkout_dir() {
  local root="$1"
  local rel_or_abs="$2"

  if [[ -z "$rel_or_abs" || "$rel_or_abs" == "null" ]]; then
    echo ""
    return 1
  fi

  if [[ "$rel_or_abs" == /* ]]; then
    if [[ -d "$rel_or_abs" ]]; then
      (cd "$rel_or_abs" && pwd) || echo ""
    else
      echo ""
      return 1
    fi
    return 0
  fi

  (cd "$root" && cd "$rel_or_abs" 2>/dev/null && pwd) || echo ""
}

# Args: repo_path_root checkout_abs_dir
# Echo a value suitable for repos.json "path": relative to repo_path_root when possible, else absolute.
filesync_path_for_repos_json() {
  local rroot="$1"
  local checkout="$2"
  rroot="$(cd "$rroot" && pwd -P)"
  checkout="$(cd "$checkout" && pwd -P)"
  if command -v realpath >/dev/null 2>&1; then
    local rel
    if rel="$(realpath --relative-to="$rroot" "$checkout" 2>/dev/null)" && [[ -n "$rel" ]]; then
      printf '%s\n' "$rel"
      return 0
    fi
  fi
  printf '%s\n' "$checkout"
}
