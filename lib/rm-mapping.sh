#!/usr/bin/env bash
# Remove one row from files.json by local_path; strip non-master marker on disk if file exists.
# Requires: colors.sh (RED/GREEN), markers.sh (strip_non_master_filesync_marker_lines).

filesync_remove_file_mapping_row() {
  local project_root="$1"
  local files_file="$2"
  local local_path="$3"
  local full="$project_root/$local_path"

  if ! jq -e --arg local "$local_path" 'any(.local_path == $local)' "$files_file" &>/dev/null; then
    echo -e "${RED}Error: No mapping for '$local_path'.${NC}" >&2
    return 1
  fi

  jq --arg local "$local_path" 'map(select(.local_path != $local))' "$files_file" > "${files_file}.tmp"
  mv "${files_file}.tmp" "$files_file"
  echo -e "${GREEN}Removed mapping:${NC} local_path=$local_path" >&2

  if [[ -f "$full" ]]; then
    local t
    t="$(mktemp)"
    strip_non_master_filesync_marker_lines "$full" "$t"
    mv "$t" "$full"
    echo -e "${GREEN}Removed local filesync marker (left kind=master if present):${NC} $local_path" >&2
  fi
}
