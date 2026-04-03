#!/usr/bin/env bash
# merge_using_git: probe repo checkout for git, backfill repos.json rows.

# shellcheck source=paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths.sh"

# Args: absolute directory
# Exit 0 if directory exists and is inside a git work tree.
filesync_dir_is_git_worktree() {
  local d="${1:?}"
  [[ -d "$d" ]] || return 1
  git -C "$d" rev-parse --is-inside-work-tree &>/dev/null
}

# Args: repo_path_root, path field from repos.json (relative or absolute)
# Prints true or false.
filesync_merge_using_git_probe_echo() {
  local rroot="${1:?}"
  local rel_or_abs="${2:?}"
  local abs=""
  abs="$(filesync_resolve_repo_checkout_dir "$rroot" "$rel_or_abs" 2>/dev/null)" || true
  if [[ -n "$abs" ]] && filesync_dir_is_git_worktree "$abs"; then
    printf '%s\n' true
  else
    printf '%s\n' false
  fi
}

# Args: repos_json_path repo_path_root
# Rewrites repos file so every row has merge_using_git (preserves existing boolean values).
filesync_repos_json_backfill_merge_using_git() {
  local repos_file="${1:?}"
  local rroot="${2:?}"
  local acc tmpf line p
  acc="$(mktemp)"
  tmpf="$(mktemp)"
  : >"$acc"
  while IFS= read -r line; do
    if jq -e '(.merge_using_git | type) == "boolean"' <<<"$line" &>/dev/null; then
      printf '%s\n' "$line" >>"$acc"
      continue
    fi
    p="$(jq -r '.path // ""' <<<"$line")"
    if [[ "$(filesync_merge_using_git_probe_echo "$rroot" "$p")" == true ]]; then
      jq -c '. + {merge_using_git: true}' <<<"$line" >>"$acc"
    else
      jq -c '. + {merge_using_git: false}' <<<"$line" >>"$acc"
    fi
  done < <(jq -c '.[]' "$repos_file")
  jq -s '.' "$acc" >"$tmpf"
  mv "$tmpf" "$repos_file"
  rm -f "$acc"
}
