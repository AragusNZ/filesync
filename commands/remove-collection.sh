#!/usr/bin/env bash
# CLI: filesync remove-collection — drop a collection from collections.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync remove-collection <name>
Alias: rmcol

Remove a named collection from .filesync/collections.json.

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/data-names.sh"
filesync_command_init_lite "${BASH_SOURCE[0]}"

if [[ $# -ne 1 ]] || [[ "$1" == -* ]]; then
  echo -e "${RED}Usage: filesync remove-collection <name>${NC}" >&2
  exit 1
fi

NAME="$1"
coll="$FILESYNC_DIR/$FILESYNC_COLLECTIONS_NAME"

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
