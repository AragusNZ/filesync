#!/usr/bin/env bash
# argv helper for per-command -h / --help (sourced by commands/*.sh).

filesync_argv_wants_help() {
  local _a
  for _a in "$@"; do
    if [[ "$_a" == '-h' || "$_a" == '--help' ]]; then
      return 0
    fi
  done
  return 1
}
