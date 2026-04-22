#!/usr/bin/env bash
# doctor clean: remove non-master filesync markers from untracked (ghost) files.
# Usage: filesync doctor clean

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync doctor clean'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}

Scan the current project and remove ghost filesync markers.

A ghost marker is any filesync marker whose kind is not master, where the file path is not present
as local_path in this project's .filesync/files.json.

What clean does:
  - Keeps kind=master markers unchanged
  - Keeps non-master markers for tracked local_path rows
  - Removes non-master marker lines from ghost files

EOF
  exit 0
fi

if [[ $# -gt 0 ]]; then
  filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
  exit 1
fi

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

filesync_clean_find_print0() {
  find "$PROJECT_ROOT" \( -name .git -o -name node_modules \) -prune -o -type f -print0 2>/dev/null
}

SCANNED=0
MARKER_FILES=0
TRACKED_NON_MASTER=0
GHOSTS_CLEANED=0

while IFS= read -r -d '' f; do
  [[ -f "$f" ]] || continue
  SCANNED=$((SCANNED + 1))

  if ! has_any_file_sync_marker "$f" 2>/dev/null; then
    continue
  fi

  MARKER_FILES=$((MARKER_FILES + 1))

  if has_master_file_sync_marker "$f" 2>/dev/null; then
    continue
  fi

  rel_path="${f#"$PROJECT_ROOT"/}"
  if jq -e --arg lp "$rel_path" 'any(.[]?; (.local_path // "") == $lp)' "$FILESYNC_FILES_FILE" >/dev/null 2>&1; then
    TRACKED_NON_MASTER=$((TRACKED_NON_MASTER + 1))
    continue
  fi

  tmp="$(mktemp)"
  strip_non_master_filesync_marker_lines "$f" "$tmp"
  mv "$tmp" "$f"
  GHOSTS_CLEANED=$((GHOSTS_CLEANED + 1))
  echo "cleaned ghost marker: $rel_path" >&2
done < <(filesync_clean_find_print0)

echo "filesync doctor clean: scanned=$SCANNED marker_files=$MARKER_FILES tracked_non_master=$TRACKED_NON_MASTER ghosts_cleaned=$GHOSTS_CLEANED" >&2
exit 0
