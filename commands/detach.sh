#!/usr/bin/env bash
# Keep mapping; set detached status + detached marker on disk.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync detach file <local_path> [<local_path> ...]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: d, d -f

Keep each mapping but pause syncing: mark the row detached and write the detached marker on disk.
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/progress.sh"

trap 'filesync_progress_end || true; rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

if [[ $# -lt 1 ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
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

_dpaths=${#LOCAL_PATHS[@]}
if filesync_progress_want "$_dpaths"; then
  filesync_progress_begin "$_dpaths"
fi
_dpi=0

detach_one() {
  local local_path="$1"
  local full="$PROJECT_ROOT/$local_path"

  if ! jq -e --arg local "$local_path" 'any(.local_path == $local)' "$FILESYNC_FILES_FILE" &>/dev/null; then
    echo -e "${RED}Error: No mapping for local_path '$local_path'.${NC}" >&2
    return 1
  fi

  local repo_file_path repo_name repo_id
  repo_file_path="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .repo_file_path // ""' "$FILESYNC_FILES_FILE")"
  repo_id="$(jq -r --arg local "$local_path" '.[] | select(.local_path == $local) | .repo_id // ""' "$FILESYNC_FILES_FILE")"
  if [[ -z "$repo_id" || "$repo_id" == "null" ]]; then
    echo -e "${RED}Error: Missing repo_id for $local_path (run: filesync migrate)${NC}" >&2
    return 1
  fi
  repo_name="$(filesync_repo_name_from_id "$FILESYNC_REPOS_FILE" "$repo_id")"
  if [[ -z "$repo_name" ]]; then
    echo -e "${RED}Error: Unknown repo_id '$repo_id' for $local_path${NC}" >&2
    return 1
  fi

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
    if render_detached_marker_file "$full" "$t" "$repo_file_path" "$repo_name" "$marker_style" "$repo_id"; then
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
  _dpi=$((_dpi + 1))
  if [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]]; then
    filesync_progress_update "$_dpi"
  fi
done

filesync_progress_end
