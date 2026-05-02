#!/usr/bin/env bash
# Assemble merged preferences, repo_path_root, global repos, and project files for jq consumers.

# shellcheck source=data-names.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data-names.sh"
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/preferences-merge.sh"
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/system-resolve.sh"
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/repos-json.sh"

# Requires: FILESYNC_PKG_ROOT, FILESYNC_DIR, FILESYNC_SYSTEM_HOME, PROJECT_ROOT
# Uses slurpfile so large files.json arrays do not hit shell argv limits.

filesync_export_data_paths() {
  export FILESYNC_SYSTEM_HOME
  export FILESYNC_REPOS_FILE="${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"
  export FILESYNC_COLLECTIONS_FILE="${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_COLLECTIONS_NAME}"
  export FILESYNC_FILES_FILE="${FILESYNC_DIR}/${FILESYNC_FILES_NAME}"
  export FILESYNC_SYSTEM_JSON="${FILESYNC_SYSTEM_HOME}/${FILESYNC_SYSTEM_NAME}"
  export FILESYNC_PREFERENCES_FILE="${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME}"
}

# Args: nameref tmpdir_var, nameref merged_prefs_path_var, mode: full|catalog
# full: stderr on merge/JSON failures; validates files.json is an array.
# catalog: quiet merge failure; no merged-prefs JSON check; no files.json check.
filesync_json_state_prepare_merged_prefs_validate_repos() {
  local -n _js_out_tmpd="$1"
  local -n _js_out_merged="$2"
  local mode="${3:?}"
  # Use names that do not shadow caller tmpd/merged_prefs; nameref binds to same-named locals first.
  local _js_workdir _js_prefs_file
  [[ "$mode" == full || "$mode" == catalog ]] || return 1
  _js_workdir="$(mktemp -d)" || return 1
  _js_prefs_file="$_js_workdir/prefs.json"

  if [[ "$mode" == full ]]; then
    if ! filesync_merged_preferences > "$_js_prefs_file"; then
      rm -rf "$_js_workdir"
      echo "filesync: could not merge preferences (check ${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME} and share/defaults/preferences.default.json)" >&2
      return 1
    fi
    if ! jq -e . "$_js_prefs_file" &>/dev/null; then
      rm -rf "$_js_workdir"
      echo "filesync: merged preferences is not valid JSON" >&2
      return 1
    fi
  else
    if ! filesync_merged_preferences > "$_js_prefs_file"; then
      rm -rf "$_js_workdir"
      return 1
    fi
  fi

  if ! jq -e 'type == "array"' "${FILESYNC_REPOS_FILE}" &>/dev/null; then
    rm -rf "$_js_workdir"
    echo "filesync: ${FILESYNC_REPOS_FILE} must be a JSON array" >&2
    return 1
  fi
  if ! filesync_assert_global_repos_unique_names "${FILESYNC_REPOS_FILE}"; then
    rm -rf "$_js_workdir"
    return 1
  fi
  if ! filesync_assert_global_repos_have_merge_using_git "${FILESYNC_REPOS_FILE}"; then
    rm -rf "$_js_workdir"
    return 1
  fi

  if [[ "$mode" == full ]]; then
    if ! jq -e 'type == "array"' "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" &>/dev/null; then
      rm -rf "$_js_workdir"
      echo "filesync: ${FILESYNC_DIR}/${FILESYNC_FILES_NAME} must be a JSON array" >&2
      return 1
    fi
  fi

  _js_out_tmpd="$_js_workdir"
  _js_out_merged="$_js_prefs_file"
  return 0
}

filesync_assemble_state_to() {
  local out="${1:-}"
  local tmpd merged_prefs rroot
  filesync_json_state_prepare_merged_prefs_validate_repos tmpd merged_prefs full || return 1

  rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"

  if ! jq -n \
    --slurpfile prefs "$merged_prefs" \
    --slurpfile repos "${FILESYNC_REPOS_FILE}" \
    --slurpfile files "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" \
    --arg rroot "$rroot" '
    ($repos[0] // []) as $R
    | ($files[0] // []) as $F
    | (($prefs[0] // {})
        | if type != "object" then {} else . end
        | del(.repos, .files, .repo_path_root)) as $pc
    | $pc * {
        repos: $R,
        files: ($F | map(
          . as $row
          | if (($row.repo_id // "") == "" or ($row.repo_id == null)) then
              error("files.json row local_path=\($row.local_path // "?"): has no repo_id (set repo_id to a catalog repo id or remove the row)")
            else
              (first($R[] | select(.id == $row.repo_id) | .name) // null) as $n
              | if $n == null then
                  error("files.json row local_path=\($row.local_path // "?"): unknown repo_id \($row.repo_id)")
                else
                  $row + {repo_name: $n}
                end
            end
        )),
        repo_path_root: $rroot
      }' >"${out:-/dev/stdout}"; then
    rm -rf "$tmpd"
    echo "filesync: could not assemble project state (check global repos, files.json, preferences)" >&2
    return 1
  fi
  rm -rf "$tmpd"
}

# Merged prefs + global repos + empty files + repo_path_root (list repos / global-only tools).
filesync_assemble_global_catalog_state_to() {
  local out="${1:?}"
  local tmpd merged_prefs rroot
  filesync_json_state_prepare_merged_prefs_validate_repos tmpd merged_prefs catalog || return 1

  rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"
  if ! jq -n \
    --slurpfile prefs "$merged_prefs" \
    --slurpfile repos "${FILESYNC_REPOS_FILE}" \
    --argjson files '[]' \
    --arg rroot "$rroot" \
    '(($prefs[0] // {})
        | if type != "object" then {} else . end
        | del(.repos, .files, .repo_path_root)) as $pc
      | $pc * {repos: ($repos[0] // []), files: $files, repo_path_root: $rroot}' > "$out"; then
    rm -rf "$tmpd"
    return 1
  fi
  rm -rf "$tmpd"
}
