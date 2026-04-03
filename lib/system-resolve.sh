#!/usr/bin/env bash
# Resolve system metadata home (repos, collections, preferences, system.json).

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data-names.sh"

# XDG config dir for pointer file (default ~/.config).
filesync_xdg_config_dir() {
  printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# Pointer file: one line = absolute path to system metadata directory.
filesync_system_home_pointer_path() {
  printf '%s/filesync/system_home' "$(filesync_xdg_config_dir)"
}

# Default metadata directory (after optional legacy migration).
filesync_system_home_default_dir() {
  local legacy="${HOME:?}/.filesync"
  local preferred="${HOME}/.filesync-root"
  if [[ -d "$legacy" && ! -e "$preferred" ]]; then
    if mv "$legacy" "$preferred" 2>/dev/null; then
      echo "filesync: migrated metadata from $legacy to $preferred" >&2
    fi
  fi
  printf '%s' "$preferred"
}

# Print absolute path to system metadata home (mkdir -p not implied for default path).
filesync_system_home_dir() {
  if [[ -n "${FILESYNC_HOME:-}" ]]; then
    mkdir -p "$FILESYNC_HOME"
    (cd "$FILESYNC_HOME" && pwd) && return 0
    echo "filesync: FILESYNC_HOME is not a directory: $FILESYNC_HOME" >&2
    return 1
  fi
  local ptr line
  ptr="$(filesync_system_home_pointer_path)"
  if [[ -f "$ptr" ]]; then
    line="$(tr -d '\r\n' <"$ptr")"
    if [[ -n "$line" ]]; then
      if (cd "$line" 2>/dev/null && pwd); then
        return 0
      fi
      echo "filesync: warning: invalid path in pointer file $ptr — using default metadata directory" >&2
    fi
  fi
  filesync_system_home_default_dir
}

# Fixed anchor for relative paths in global repos.json: $HOME, unless
# FILESYNC_REPO_PATH_ANCHOR is set (tests / automation with isolated checkouts).
# Optional first argument (system home) is ignored; kept for call-site compatibility.
filesync_read_repo_path_root() {
  if [[ -n "${FILESYNC_REPO_PATH_ANCHOR:-}" ]]; then
    (cd "$FILESYNC_REPO_PATH_ANCHOR" && pwd -P)
    return 0
  fi
  (cd "${HOME:?}" && pwd -P)
}

# Ensure system home exists with default JSON files. Prints absolute home path.
filesync_ensure_system_store() {
  local home sys repos coll prefs
  home="$(filesync_system_home_dir)" || return 1
  mkdir -p "$home"
  sys="$home/${FILESYNC_SYSTEM_NAME}"
  repos="$home/${FILESYNC_GLOBAL_REPOS_NAME}"
  coll="$home/${FILESYNC_GLOBAL_COLLECTIONS_NAME}"
  prefs="$home/${FILESYNC_PREFERENCES_NAME}"

  if [[ ! -f "$sys" ]]; then
    jq -n '{version: 2}' >"$sys"
  fi
  if [[ ! -f "$repos" ]]; then
    printf '%s\n' '[]' | jq . >"$repos"
  fi
  if [[ ! -f "$coll" ]]; then
    printf '%s\n' '[]' | jq . >"$coll"
  fi
  if [[ ! -f "$prefs" ]]; then
    printf '%s\n' '{}' | jq . >"$prefs"
  fi
  printf '%s' "$home"
}

# Write pointer file so future invocations use this metadata directory.
filesync_write_system_home_pointer() {
  local target="${1:?}"
  local ptr dir
  ptr="$(filesync_system_home_pointer_path)"
  dir="$(dirname "$ptr")"
  mkdir -p "$dir"
  target="$(cd "$target" && pwd)"
  printf '%s\n' "$target" >"$ptr"
}
