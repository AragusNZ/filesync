#!/usr/bin/env bash
# filesync doctor: inspections and cleanup tools.
# Usage: filesync doctor [inspect|clean]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync doctor [inspect|clean]'
if [[ "${1:-}" != "clean" ]] && filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}

Health and integrity tools.

Commands:
  inspect   Validate catalog/project markers and mappings (default)
  clean     Remove ghost non-master marker lines from untracked files

Examples:
  filesync doctor
  filesync doctor inspect
  filesync doctor clean
EOF
  exit 0
fi

target="${1:-inspect}"
case "$target" in
  inspect)
    if [[ $# -gt 1 ]]; then
      filesync_unexpected_arg_stderr "$2" 'Usage: filesync doctor [inspect]'
      exit 1
    fi
    exec "$_CMD_ROOT/doctor-inspect.sh"
    ;;
  clean)
    shift || true
    exec "$_CMD_ROOT/doctor-clean.sh" "$@"
    ;;
  *)
    filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
    exit 1
    ;;
esac
