#!/usr/bin/env bash
# Detach every files.json row for a given repo_name (same per-file behavior as detach-file).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync detach-repo <repo_name>
Alias: ddr

Detach every files.json row for the given repo_name (same per-file behavior as detach-file).
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

if [[ $# -ne 1 ]] || [[ -z "${1// }" ]]; then
  echo -e "${RED}Usage: filesync detach-repo|ddr <repo_name>${NC}" >&2
  exit 1
fi

REPO_NAME="$1"
if [[ "$REPO_NAME" == -* ]]; then
  echo -e "${RED}Usage: filesync detach-repo|ddr <repo_name>${NC}" >&2
  exit 1
fi

declare -a LOCAL_PATHS=()
while IFS= read -r _lp; do
  [[ -z "$_lp" || "$_lp" == "null" ]] && continue
  LOCAL_PATHS+=("$_lp")
done < <(jq -r --arg r "$REPO_NAME" '.[] | select(.repo_name == $r) | .local_path' "$FILESYNC_FILES_FILE")

if [[ ${#LOCAL_PATHS[@]} -eq 0 ]]; then
  echo -e "${RED}Error: No file mappings for repo_name='$REPO_NAME'.${NC}" >&2
  exit 1
fi

exec "$_CMD_ROOT/detach.sh" "${LOCAL_PATHS[@]}"
