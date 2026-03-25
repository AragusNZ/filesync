#!/usr/bin/env bash
# Keep mapping; set detached status + detached marker on disk.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage: filesync detach <local_path1> [local_path2 ...]${NC}" >&2
  exit 1
fi

declare -a LOCAL_PATHS=()
declare -A SEEN_LOCAL_PATHS=()
for arg in "$@"; do
  [[ -n "$arg" ]] || { echo -e "${RED}Error: empty local_path${NC}" >&2; exit 1; }
  [[ -z "${SEEN_LOCAL_PATHS[$arg]:-}" ]] || { echo -e "${RED}Error: duplicate '$arg'${NC}" >&2; exit 1; }
  SEEN_LOCAL_PATHS["$arg"]=1
  LOCAL_PATHS+=("$arg")
done

detach_one() {
  local local_path="$1"
  local full="$PROJECT_ROOT/$local_path"

  if ! jq -e --arg local "$local_path" 'any(.local_path == $local)' "$FILESYNC_FILES_FILE" &>/dev/null; then
    echo -e "${RED}Error: No mapping for local_path '$local_path'.${NC}" >&2
    return 1
  fi

  local repo_file_path repo_name
  repo_file_path="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .repo_file_path // ""' "$FILESYNC_FILES_FILE")"
  repo_name="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .repo_name // ""' "$FILESYNC_FILES_FILE")"

  jq --arg local "$local_path" \
    'map(if .local_path == $local then . + {sync_status: "detached"} else . end)' \
    "$FILESYNC_FILES_FILE" > "${FILESYNC_FILES_FILE}.tmp"
  mv "${FILESYNC_FILES_FILE}.tmp" "$FILESYNC_FILES_FILE"
  echo -e "${GREEN}Detached:${NC} local_path=$local_path" >&2

  if [[ -f "$full" ]]; then
    local t
    t="$(mktemp)"
    local marker_style=""
    marker_style="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .marker_style // empty' "$FILESYNC_FILES_FILE" | head -1)"
    [[ "$marker_style" == "null" ]] && marker_style=""
    if render_detached_marker_file "$full" "$t" "$repo_file_path" "$repo_name" "$marker_style"; then
      cp "$t" "$full"
      echo -e "${GREEN}Updated marker:${NC} $local_path" >&2
    else
      filesync_warn "could not rewrite marker in $local_path"
    fi
    rm -f "$t"
  fi
}

for lp in "${LOCAL_PATHS[@]}"; do
  detach_one "$lp" || filesync_die "detach failed for one or more paths (see messages above)"
done
