#!/usr/bin/env bash
# Discover .filesync directory and project root.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/data-names.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/colors.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/log.sh"

# Optional overrides: FILESYNC_DIR, FILESYNC_PROJECT_ROOT

# When cwd lies inside a registered repo checkout that has .filesync/files.json, use that project root.
filesync_try_discover_from_registered_repos() {
  local cwd="${1:?}"
  local _libdir
  _libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_libdir}/system-resolve.sh"
  # shellcheck source=/dev/null
  source "${_libdir}/paths.sh"
  # shellcheck source=/dev/null
  source "${_libdir}/filesync-projects.sh"
  local home
  home="$(filesync_system_home_dir 2>/dev/null)" || return 1
  local repos="$home/${FILESYNC_GLOBAL_REPOS_NAME}"
  [[ -f "$repos" ]] || return 1
  local rroot
  rroot="$(filesync_read_repo_path_root "$home")"
  [[ -z "$rroot" ]] && return 1
  local root
  root="$(filesync_project_root_from_registered_repos "$cwd" "$home" "$rroot" "$repos")"
  [[ -z "$root" ]] && return 1
  PROJECT_ROOT="$root"
  FILESYNC_DIR="$root/.filesync"
  export PROJECT_ROOT FILESYNC_DIR
  return 0
}

filesync_resolve_or_exit() {
  if [[ -n "${FILESYNC_PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$FILESYNC_PROJECT_ROOT" && pwd)"
    FILESYNC_DIR="${FILESYNC_DIR:-$PROJECT_ROOT/.filesync}"
    export PROJECT_ROOT FILESYNC_DIR
    if [[ ! -d "$FILESYNC_DIR" ]]; then
      filesync_error "directory not found: $FILESYNC_DIR (FILESYNC_PROJECT_ROOT=$PROJECT_ROOT)"
      exit 1
    fi
    return 0
  fi

  if [[ -n "${FILESYNC_DIR:-}" ]]; then
    FILESYNC_DIR="$(cd "$FILESYNC_DIR" && pwd)"
    PROJECT_ROOT="$(dirname "$FILESYNC_DIR")"
    export PROJECT_ROOT FILESYNC_DIR
    return 0
  fi

  local dir
  dir="$(pwd -P)"
  if filesync_try_discover_from_registered_repos "$dir"; then
    return 0
  fi
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.filesync" ]]; then
      PROJECT_ROOT="$dir"
      FILESYNC_DIR="$dir/.filesync"
      export PROJECT_ROOT FILESYNC_DIR
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  filesync_error "no .filesync directory found (walked up from $(pwd -P))"
  filesync_error "create .filesync/${FILESYNC_FILES_NAME} (see docs/configuration.md in the filesync repository)."
  exit 1
}

filesync_require_files() {
  local missing=0
  [[ -f "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" ]] || { filesync_error "missing ${FILESYNC_DIR}/${FILESYNC_FILES_NAME}"; missing=1; }
  if [[ "$missing" -eq 1 ]]; then
    exit 1
  fi
}
