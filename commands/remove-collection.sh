#!/usr/bin/env bash
# CLI: filesync remove collection — drop a collection from collections.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync remove collection <name>'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: rm -col

Remove a named repo group from collections.json. Repos themselves are unchanged; only the grouping is
dropped.

Arguments:

  <name>    Collection name to delete.

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

if [[ $# -ne 1 ]] || [[ "$1" == -* ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

NAME="$1"
coll="$FILESYNC_COLLECTIONS_FILE"

if [[ ! -f "$coll" ]]; then
  echo -e "${RED}Error: No collections file at $coll${NC}" >&2
  exit 1
fi

if ! jq -e --arg n "$NAME" 'any(.name == $n)' "$coll" &>/dev/null; then
  echo -e "${RED}Error: No collection named '$NAME'${NC}" >&2
  exit 1
fi

tmp="$(mktemp)"
jq --arg n "$NAME" 'map(select(.name != $n))' "$coll" > "$tmp"
mv "$tmp" "$coll"

echo -e "${GREEN}Removed collection:${NC} $NAME" >&2
