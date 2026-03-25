#!/usr/bin/env bash
# External command checks (requires lib/colors.sh to be sourced first).

filesync_require_jq() {
  if ! command -v jq &>/dev/null; then
    # shellcheck disable=SC2154
    filesync_error "jq is required but not installed."
    exit 1
  fi
}

filesync_require_git() {
  if ! command -v git &>/dev/null; then
    # shellcheck disable=SC2154
    filesync_error "git is required but not installed."
    exit 1
  fi
}
