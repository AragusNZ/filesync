#!/usr/bin/env bash
# CLI: filesync new collection — append a named repo group to collections.json.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync new collection <name> [--repos=a,b]
Also: n -col

Create a collection in the global collections.json for use with add file / add master / add clone --also=.
Collection names must not match any repo name in the global repos.json.

Options:
  --repos=a,b   Optional initial members (each must exist in global repos.json)

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
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync new collection <name> [--repos=a,b]" >&2
      exit 1
      ;;
    *)
      if [[ -n "$NAME" ]]; then
        echo -e "${RED}Unexpected argument: $1${NC}" >&2
        exit 1
      fi
      NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo -e "${RED}Usage: filesync new collection <name> [--repos=a,b]${NC}" >&2
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
