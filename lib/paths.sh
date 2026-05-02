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

# Args: repo_path_root, default_checkout_abs_dir, user_line (empty → use default checkout)
# Prints repos.json path field (relative to repo_path_root when possible). Returns 1 if user_line is
# non-empty but does not resolve to an existing directory under the usual rules.
filesync_repos_json_path_from_input() {
  local rroot="$1" default_abs="$2" raw="${3-}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  local checkout_abs
  rroot="$(cd "$rroot" && pwd -P)" || return 1
  default_abs="$(cd "$default_abs" && pwd -P)" || return 1
  if [[ -z "$raw" ]]; then
    checkout_abs="$default_abs"
  elif [[ "$raw" == /* ]]; then
    checkout_abs="$(cd "$raw" 2>/dev/null && pwd -P)" || return 1
  else
    checkout_abs="$(cd "$rroot" && cd -- "$raw" 2>/dev/null && pwd -P)" || return 1
  fi
  [[ -d "$checkout_abs" ]] || return 1
  filesync_path_for_repos_json "$rroot" "$checkout_abs"
}

# Args: path to an existing file or directory (relative or absolute).
# Prints one absolute path with directory symlinks resolved (pwd -P); uses realpath(1) when available.
# Returns 1 if the path does not exist.
filesync_canonical_existing() {
  local p="${1:?}"
  [[ -e "$p" ]] || return 1
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null && return 0
  fi
  local d bn
  d="$(dirname -- "$p")"
  bn="$(basename -- "$p")"
  if [[ "$d" == "." ]]; then
    d="$(pwd -P)"
  else
    d="$(cd "$d" && pwd -P)" || return 1
  fi
  printf '%s/%s\n' "$d" "$bn"
}
