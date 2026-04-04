#!/usr/bin/env bash
# argv and usage helpers for commands/*.sh and compound-dispatch.sh.
#
# Conventions:
# - Full help (-h / --help): print to stdout (pipe-friendly), then exit 0 from the caller.
# - Usage / unknown option / bad arity: print to stderr; use filesync_*_stderr helpers below.
# - Caller should define one FILESYNC_CMD_USAGE='Usage: filesync …' and reuse for heredoc + errors.

_CLI_HELP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${RED:-}" ]] && [[ -r "${_CLI_HELP_LIB}/colors.sh" ]]; then
  # shellcheck source=/dev/null
  source "${_CLI_HELP_LIB}/colors.sh"
fi

filesync_argv_wants_help() {
  local _a
  for _a in "$@"; do
    if [[ "$_a" == '-h' || "$_a" == '--help' ]]; then
      return 0
    fi
  done
  return 1
}

# Args: full usage line (include leading "Usage: ")
filesync_usage_error_stderr() {
  # shellcheck disable=SC2154
  echo -e "${RED}$1${NC}" >&2
}

# Args: bad_option usage_line
filesync_unknown_option_stderr() {
  # shellcheck disable=SC2154
  echo -e "${RED}Unknown option: $1${NC}" >&2
  filesync_usage_error_stderr "$2"
}

# Args: bad_arg usage_line
filesync_unexpected_arg_stderr() {
  # shellcheck disable=SC2154
  echo -e "${RED}Unexpected argument: $1${NC}" >&2
  filesync_usage_error_stderr "$2"
}

# Combined multi-script --help on stdout (bold headers). Requires colors (BOLD, WHITE, NC).
# Args: pkg_root title label1 script1 [label2 script2 ...]
# Each script is basename under pkg_root/commands/ (e.g. info-file.sh).
filesync_print_compound_help_stdout() {
  local pkg_root="${1:?}" title="$2"
  shift 2
  # shellcheck disable=SC2154
  echo -e "${BOLD}${WHITE}${title}${NC}"
  echo ""
  while [[ $# -ge 2 ]]; do
    local label="$1" script="$2"
    shift 2
    echo -e "${BOLD}--- ${label} ---${NC}"
    echo ""
    bash "${pkg_root}/commands/${script}" --help
    echo ""
  done
}
