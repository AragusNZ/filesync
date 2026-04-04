#!/usr/bin/env bash
# CLI: filesync new collection — append a named repo group to collections.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync new collection <name> [--repos=a,b]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: n -col

Create a named group of repos in collections.json for use with add file / add master / add clone --also=.
The name must not match any existing repo name in repos.json.

Options:
  --repos=a,b   Optional starting members (each must already exist in repos.json)

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/data-names.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
filesync_command_init_system "${BASH_SOURCE[0]}"

NAME=""
REPOS_CSV=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos=*)
      REPOS_CSV="${1#*=}"
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      if [[ -n "$NAME" ]]; then
        filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
        exit 1
      fi
      NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "$NAME" ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

repos="$FILESYNC_REPOS_FILE"
coll="$FILESYNC_COLLECTIONS_FILE"

if jq -e --arg n "$NAME" 'any(.name == $n)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: '$NAME' is already a repo name; choose a different collection name.${NC}" >&2
  exit 1
fi

if filesync_collections_name_taken "$coll" "$NAME"; then
  echo -e "${RED}Error: Collection '$NAME' already exists.${NC}" >&2
  exit 1
fi

declare -a REPO_MEMBERS=()
if [[ -n "$REPOS_CSV" ]]; then
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "$line" ]] && continue
    REPO_MEMBERS+=("$line")
  done < <(echo "$REPOS_CSV" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | awk '!seen[$0]++')
fi

for r in "${REPO_MEMBERS[@]}"; do
  if ! jq -e --arg n "$r" 'any(.name == $n)' "$repos" &>/dev/null; then
    echo -e "${RED}Error: Repo '$r' not found in global repos.json${NC}" >&2
    exit 1
  fi
done

repos_json='[]'
if [[ ${#REPO_MEMBERS[@]} -gt 0 ]]; then
  repos_json=$(printf '%s\n' "${REPO_MEMBERS[@]}" | jq -R . | jq -s -c 'unique')
fi

tmp="$(mktemp)"
if ! jq --arg n "$NAME" --argjson rlist "$repos_json" '. + [{name: $n, repos: $rlist}]' "$coll" > "$tmp"; then
  rm -f "$tmp"
  exit 1
fi
mv "$tmp" "$coll"

echo -e "${GREEN}Added collection:${NC} $NAME repos=$(jq -c --arg n "$NAME" '.[] | select(.name == $n) | .repos' "$coll")" >&2
