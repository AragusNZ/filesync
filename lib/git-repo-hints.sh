#!/usr/bin/env bash
# Best-effort git metadata for interactive repo registration (init / add-repo).

# From a directory (typically a filesync project root), set hint variables when inside a git work tree:
#   FILESYNC_GIT_HINT_TOP     — absolute path to git work tree root
#   FILESYNC_GIT_HINT_URL     — remote URL (origin, else first remote), or empty
#   FILESYNC_GIT_HINT_BRANCH  — current branch name, or empty if detached / unknown
filesync_git_collect_hints() {
  local start_dir="${1:?}"
  FILESYNC_GIT_HINT_TOP=""
  FILESYNC_GIT_HINT_URL=""
  FILESYNC_GIT_HINT_BRANCH=""
  command -v git >/dev/null 2>&1 || return 0
  [[ -d "$start_dir" ]] || return 0
  git -C "$start_dir" rev-parse --is-inside-work-tree &>/dev/null || return 0
  local top
  top="$(git -C "$start_dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  FILESYNC_GIT_HINT_TOP="$(cd "$top" && pwd -P)"
  if git -C "$FILESYNC_GIT_HINT_TOP" remote get-url origin &>/dev/null; then
    FILESYNC_GIT_HINT_URL="$(git -C "$FILESYNC_GIT_HINT_TOP" remote get-url origin 2>/dev/null)"
  else
    local r0
    r0="$(git -C "$FILESYNC_GIT_HINT_TOP" remote 2>/dev/null | head -1)"
    if [[ -n "$r0" ]]; then
      # shellcheck disable=SC2034  # out-param read by init / callers
      FILESYNC_GIT_HINT_URL="$(git -C "$FILESYNC_GIT_HINT_TOP" remote get-url "$r0" 2>/dev/null)"
    fi
  fi
  FILESYNC_GIT_HINT_BRANCH="$(git -C "$FILESYNC_GIT_HINT_TOP" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [[ "$FILESYNC_GIT_HINT_BRANCH" == "HEAD" ]]; then
    FILESYNC_GIT_HINT_BRANCH=""
  fi
  return 0
}
