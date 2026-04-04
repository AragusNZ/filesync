#!/usr/bin/env bash
# Detach every files.json row for a given repo_name (same per-file behavior as detach file).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync detach files-in-repo <repo_name>'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: d -fir

Detach every files.json row for the given repo_name (same per-file behavior as detach file).
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

if [[ $# -ne 1 ]] || [[ -z "${1// }" ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

REPO_NAME="$1"
if [[ "$REPO_NAME" == -* ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

_repo_id="$(filesync_global_repos_id_for_name "$FILESYNC_REPOS_FILE" "$REPO_NAME")"
if [[ -z "$_repo_id" ]]; then
  echo -e "${RED}Error: Repo '$REPO_NAME' not found in global repos.${NC}" >&2
  exit 1
fi

declare -a LOCAL_PATHS=()
while IFS= read -r _lp; do
  [[ -z "$_lp" || "$_lp" == "null" ]] && continue
  LOCAL_PATHS+=("$_lp")
done < <(jq -r --arg id "$_repo_id" '.[] | select(.repo_id == $id) | .local_path' "$FILESYNC_FILES_FILE")

if [[ ${#LOCAL_PATHS[@]} -eq 0 ]]; then
  echo -e "${RED}Error: No file mappings for repo_name='$REPO_NAME'.${NC}" >&2
  exit 1
fi

trap - EXIT
rm -f "${FILESYNC_STATE_FILE:-}"
unset FILESYNC_STATE_FILE CONFIG_FILE
exec "$_CMD_ROOT/detach.sh" "${LOCAL_PATHS[@]}"
