#!/usr/bin/env bash
# User-facing messages (stderr). Requires lib/colors.sh sourced first.

# shellcheck disable=SC2154

filesync_error() {
  echo -e "${RED}filesync:${NC} $*" >&2
}

filesync_warn() {
  echo -e "${YELLOW}filesync:${NC} $*" >&2
}

filesync_info() {
  if [[ -n "${FILESYNC_VERBOSE:-}" ]]; then
    echo -e "${WHITE}filesync:${NC} $*" >&2
  fi
}

filesync_die() {
  filesync_error "$@"
  exit 1
}

filesync_debug_err_trap() {
  local ec=$?
  echo -e "${MAGENTA}filesync:${NC} debug: command failed (exit ${ec}): ${BASH_COMMAND}" >&2
  echo -e "${MAGENTA}filesync:${NC} debug: line ${LINENO} in ${BASH_SOURCE[1]:-main}" >&2
}

filesync_log_enable_debug() {
  if [[ -n "${FILESYNC_DEBUG:-}" ]]; then
    set -E
    trap 'filesync_debug_err_trap' ERR
  fi
}
