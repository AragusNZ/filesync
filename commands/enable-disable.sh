#!/usr/bin/env bash
# Toggle check_sync_enabled for a repo in the global store (convenience wrapper).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  case "${1:-}" in
    enable)
      cat <<'EOF'
Usage: filesync enable <repo_name>

Set check_sync_enabled true for this repo in the global store (same as
filesync config repo <name> check-sync true). Prompts for confirmation.
Does not require a project .filesync.
EOF
      ;;
    disable)
      cat <<'EOF'
Usage: filesync disable <repo_name>

Set check_sync_enabled false for this repo in the global store (same as
filesync config repo <name> check-sync false).
Does not require a project .filesync.
EOF
      ;;
    *)
      echo "Usage: filesync enable <repo_name> | filesync disable <repo_name>" >&2
      ;;
  esac
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

if [[ $# -lt 2 ]]; then
  echo -e "${RED}Usage: filesync enable|disable <repo_name>${NC}" >&2
  exit 1
fi

cmd="$1"
repo="$2"

case "$cmd" in
  enable)
    read -rp "Enable check/sync for repo '$repo'? (y/N) " ans
    if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
      echo "Aborted." >&2
      exit 0
    fi
    exec "$_CMD_ROOT/config.sh" repo "$repo" check-sync true
    ;;
  disable)
    exec "$_CMD_ROOT/config.sh" repo "$repo" check-sync false
    ;;
  *)
    echo -e "${RED}Usage: filesync enable|disable <repo_name>${NC}" >&2
    exit 1
    ;;
esac
