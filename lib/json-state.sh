#!/usr/bin/env bash
# Assemble full state JSON (legacy tool-file-sync-config shape) for jq consumers.

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data-names.sh"

# Requires: FILESYNC_PKG_ROOT, FILESYNC_DIR, PROJECT_ROOT
# Uses slurpfile so large files.json arrays do not hit shell argv limits.

filesync_assemble_state_to() {
  local out="${1:-}"
  local tmpd merged_file
  tmpd="$(mktemp -d)"
  merged_file="$tmpd/cfg.json"
  filesync_merged_top_level_config > "$merged_file"

  if ! jq -e 'type == "array"' "${FILESYNC_DIR}/${FILESYNC_REPOS_NAME}" &>/dev/null; then
    rm -rf "$tmpd"
    echo "filesync: ${FILESYNC_DIR}/${FILESYNC_REPOS_NAME} must be a JSON array" >&2
    return 1
  fi
  if ! jq -e 'type == "array"' "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" &>/dev/null; then
    rm -rf "$tmpd"
    echo "filesync: ${FILESYNC_DIR}/${FILESYNC_FILES_NAME} must be a JSON array" >&2
    return 1
  fi

  # slurpfile wraps file contents as array of JSON values; one object -> [0] is the object; one array -> [0] is the array
  if [[ -n "$out" ]]; then
    jq -n \
      --slurpfile cfg "$merged_file" \
      --slurpfile repos "${FILESYNC_DIR}/${FILESYNC_REPOS_NAME}" \
      --slurpfile files "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" \
      '$cfg[0] * {repos: $repos[0], files: $files[0]}' > "$out"
  else
    jq -n \
      --slurpfile cfg "$merged_file" \
      --slurpfile repos "${FILESYNC_DIR}/${FILESYNC_REPOS_NAME}" \
      --slurpfile files "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" \
      '$cfg[0] * {repos: $repos[0], files: $files[0]}'
  fi
  rm -rf "$tmpd"
}

filesync_export_data_paths() {
  export FILESYNC_USER_CONFIG="${FILESYNC_DIR}/${FILESYNC_CONFIG_NAME}"
  export FILESYNC_REPOS_FILE="${FILESYNC_DIR}/${FILESYNC_REPOS_NAME}"
  export FILESYNC_FILES_FILE="${FILESYNC_DIR}/${FILESYNC_FILES_NAME}"
  export FILESYNC_CONFIG_NAME FILESYNC_REPOS_NAME FILESYNC_FILES_NAME
}

filesync_user_config_set_last_check_at() {
  local now="$1"
  local cfg="$FILESYNC_USER_CONFIG"
  local tmp
  tmp="$(mktemp)"
  mkdir -p "$(dirname "$cfg")"
  if [[ -f "$cfg" ]]; then
    jq --arg now "$now" '. + {last_check_at: $now}' "$cfg" > "$tmp"
  else
    jq -n --arg now "$now" '{last_check_at: $now}' > "$tmp"
  fi
  mv "$tmp" "$cfg"
}
