#!/usr/bin/env bash
# Dispatched as: filesync info repo <name>  or  filesync info -r <name>  (also: i repo …, i -r …)

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync info repo <repo-name>'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
       filesync info -r <repo-name>

Also: filesync i repo <repo-name>   or   filesync i -r <repo-name>

From the current filesync project, print global catalog fields for <repo-name>, verify the
checkout directory exists (same path resolution as filesync config doctor), report how many
files.json rows reference that repo, and summarize their sync_status values (run
filesync check --repo=… to refresh).

Requires a project .filesync/ (walk-up from cwd).

For both info forms on one page: filesync info --help
EOF
  exit 0
fi

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-banner.sh"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

if [[ $# -ne 1 ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  echo "       filesync info -r <repo-name>   (see: filesync info repo --help)" >&2
  exit 1
fi

REPO_NAME="$1"

found="$(jq -e --arg n "$REPO_NAME" '.repos[] | select(.name == $n)' "$CONFIG_FILE" 2>/dev/null || true)"
if [[ -z "$found" ]]; then
  echo -e "${RED}No repo named '$REPO_NAME' in global repos.json${NC}" >&2
  exit 1
fi

rroot="$(jq -r '.repo_path_root' "$CONFIG_FILE")"
path_raw="$(jq -r --arg n "$REPO_NAME" 'first(.repos[] | select(.name == $n)) | .path // ""' "$CONFIG_FILE")"

filesync_print_info_heading "Repo: $REPO_NAME"
filesync_print_info_kv "Project root" "$PROJECT_ROOT"

filesync_print_info_heading "Catalog (repos.json)"
jq -r --arg n "$REPO_NAME" '.repos[] | select(.name == $n) |
  [
    ["Name", .name],
    ["ID", (.id // "")],
    ["Path", (.path // "")],
    ["URL", (if .url == null or .url == "" then "—" else (.url | tostring) end)],
    ["Branch", (if .branch == null or .branch == "" then "—" else (.branch | tostring) end)],
    ["merge_using_git", (.merge_using_git | tostring)],
    ["check_sync_enabled", (if (.check_sync_enabled | type) == "boolean" then (.check_sync_enabled | tostring) else "true (default when omitted)" end)],
    ["mirror_in_enabled", (if (.mirror_in_enabled | type) == "boolean" then (.mirror_in_enabled | tostring) else "true (default when omitted)" end)]
  ] | .[] | @tsv' "$CONFIG_FILE" | while IFS=$'\t' read -r _ik _iv; do
  [[ -z "${_ik:-}" ]] && continue
  filesync_print_info_kv "$_ik" "$_iv"
done

filesync_print_info_heading "Checkout"
filesync_print_info_kv "Repo path anchor" "$rroot"
resolved=""
if [[ -z "$path_raw" || "$path_raw" == "null" ]]; then
  echo -e "  ${YELLOW}Warning: repo has no path in repos.json (cannot verify checkout).${NC}" >&2
else
  filesync_print_info_kv "Configured path" "$path_raw"
  resolved="$(filesync_resolve_repo_checkout_dir "$rroot" "$path_raw" 2>/dev/null)" || true
  if [[ -n "$resolved" ]] && [[ -d "$resolved" ]]; then
    filesync_print_info_kv "Resolved checkout" "$resolved"
    echo -e "  ${GREEN}Checkout directory exists.${NC}" >&2
  else
    echo -e "  ${YELLOW}Warning: checkout path missing or not a directory (same check as filesync config doctor).${NC}" >&2
  fi
fi

filesync_print_info_heading "Mappings (this project)"
# shellcheck disable=SC2034
declare -A INFO_REPO_STATUS_COUNTS=()
count=0
while IFS=$'\t' read -r lp st || [[ -n "${lp:-}" ]]; do
  [[ -z "${lp:-}" ]] && continue
  count=$((count + 1))
  filesync_counts_inc INFO_REPO_STATUS_COUNTS "${st:-unset}"
done < <(jq -r --arg n "$REPO_NAME" '.files[] | select(.repo_name == $n) | "\(.local_path)\t\(.sync_status // "")"' "$CONFIG_FILE")

echo "  File rows linked to this repo: ${count}" >&2
if [[ "$count" -gt 0 ]]; then
  filesync_print_status_summary "file rows" "$count" INFO_REPO_STATUS_COUNTS
  echo -e "  ${GRAY}Tip: filesync check --repo=${REPO_NAME} refreshes status in files.json${NC}" >&2
else
  echo -e "  ${GRAY}(no files.json rows for this repo in this project)${NC}" >&2
fi
