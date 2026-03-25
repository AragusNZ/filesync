#!/usr/bin/env bash
# Discover .filesync directory and project root.

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data-names.sh"

# Optional overrides: FILESYNC_DIR, FILESYNC_PROJECT_ROOT

filesync_resolve_or_exit() {
  if [[ -n "${FILESYNC_PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$FILESYNC_PROJECT_ROOT" && pwd)"
    FILESYNC_DIR="${FILESYNC_DIR:-$PROJECT_ROOT/.filesync}"
    export PROJECT_ROOT FILESYNC_DIR
    if [[ ! -d "$FILESYNC_DIR" ]]; then
      echo "filesync: directory not found: $FILESYNC_DIR (FILESYNC_PROJECT_ROOT=$PROJECT_ROOT)" >&2
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
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.filesync" ]]; then
      PROJECT_ROOT="$dir"
      FILESYNC_DIR="$dir/.filesync"
      export PROJECT_ROOT FILESYNC_DIR
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  echo "filesync: no .filesync directory found (walked up from $(pwd -P))" >&2
  echo "Create .filesync/${FILESYNC_CONFIG_NAME}, ${FILESYNC_REPOS_NAME}, and ${FILESYNC_FILES_NAME} — see docs/configuration.md in the filesync repository." >&2
  exit 1
}

filesync_require_files() {
  local missing=0
  [[ -f "${FILESYNC_DIR}/${FILESYNC_REPOS_NAME}" ]] || { echo "filesync: missing ${FILESYNC_DIR}/${FILESYNC_REPOS_NAME}" >&2; missing=1; }
  [[ -f "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" ]] || { echo "filesync: missing ${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" >&2; missing=1; }
  if [[ "$missing" -eq 1 ]]; then
    exit 1
  fi
}
