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

filesync_assemble_state_to() {
  local out="${1:-}"
  local tmpd merged_prefs rroot
  tmpd="$(mktemp -d)"
  merged_prefs="$tmpd/prefs.json"
  if ! filesync_merged_preferences > "$merged_prefs"; then
    rm -rf "$tmpd"
    echo "filesync: could not merge preferences (check ${FILESYNC_SYSTEM_HOME}/${FILESYNC_PREFERENCES_NAME} and share/defaults/preferences.default.json)" >&2
    return 1
  fi
  if ! jq -e . "$merged_prefs" &>/dev/null; then
    rm -rf "$tmpd"
    echo "filesync: merged preferences is not valid JSON" >&2
    return 1
  fi

  if ! jq -e 'type == "array"' "${FILESYNC_REPOS_FILE}" &>/dev/null; then
    rm -rf "$tmpd"
    echo "filesync: ${FILESYNC_REPOS_FILE} must be a JSON array" >&2
    return 1
  fi
  if ! filesync_assert_global_repos_unique_names "${FILESYNC_REPOS_FILE}"; then
    rm -rf "$tmpd"
    return 1
  fi
  if ! filesync_assert_global_repos_have_merge_using_git "${FILESYNC_REPOS_FILE}"; then
    rm -rf "$tmpd"
    return 1
  fi
  if ! jq -e 'type == "array"' "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" &>/dev/null; then
    rm -rf "$tmpd"
    echo "filesync: ${FILESYNC_DIR}/${FILESYNC_FILES_NAME} must be a JSON array" >&2
    return 1
  fi

  rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"

  if [[ -n "$out" ]]; then
    if ! jq -n \
      --slurpfile prefs "$merged_prefs" \
      --slurpfile repos "${FILESYNC_REPOS_FILE}" \
      --slurpfile files "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" \
      --arg rroot "$rroot" '
      ($repos[0]) as $R
      | ($files[0]) as $F
      | $prefs[0] * {
          repos: $R,
          files: ($F | map(
            . as $row
            | if (($row.repo_id // "") != "" and ($row.repo_id != null)) then
                $row + {repo_name: (($R[] | select(.id == $row.repo_id) | .name) // $row.repo_name)}
              elif (($row.repo_name // "") != "" and ($row.repo_name != null)) then
                $row + {repo_id: (($R[] | select(.name == $row.repo_name) | .id) // "")}
              else $row end
          )),
          repo_path_root: $rroot
        }' > "$out"; then
      rm -rf "$tmpd"
      echo "filesync: could not assemble project state (check global repos, files.json, preferences)" >&2
      return 1
    fi
  else
    if ! jq -n \
      --slurpfile prefs "$merged_prefs" \
      --slurpfile repos "${FILESYNC_REPOS_FILE}" \
      --slurpfile files "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}" \
      --arg rroot "$rroot" '
      ($repos[0]) as $R
      | ($files[0]) as $F
      | $prefs[0] * {
          repos: $R,
          files: ($F | map(
            . as $row
            | if (($row.repo_id // "") != "" and ($row.repo_id != null)) then
                $row + {repo_name: (($R[] | select(.id == $row.repo_id) | .name) // $row.repo_name)}
              elif (($row.repo_name // "") != "" and ($row.repo_name != null)) then
                $row + {repo_id: (($R[] | select(.name == $row.repo_name) | .id) // "")}
              else $row end
          )),
          repo_path_root: $rroot
        }'; then
      rm -rf "$tmpd"
      echo "filesync: could not assemble project state (check global repos, files.json, preferences)" >&2
      return 1
    fi
  fi
  rm -rf "$tmpd"
}

# Merged prefs + global repos + empty files + repo_path_root (list repos / global-only tools).
filesync_assemble_global_catalog_state_to() {
  local out="${1:?}"
  local tmpd merged_prefs rroot
  tmpd="$(mktemp -d)"
  merged_prefs="$tmpd/prefs.json"
  if ! filesync_merged_preferences > "$merged_prefs"; then
    rm -rf "$tmpd"
    return 1
  fi
  if ! jq -e 'type == "array"' "${FILESYNC_REPOS_FILE}" &>/dev/null; then
    rm -rf "$tmpd"
    echo "filesync: ${FILESYNC_REPOS_FILE} must be a JSON array" >&2
    return 1
  fi
  if ! filesync_assert_global_repos_unique_names "${FILESYNC_REPOS_FILE}"; then
    rm -rf "$tmpd"
    return 1
  fi
  if ! filesync_assert_global_repos_have_merge_using_git "${FILESYNC_REPOS_FILE}"; then
    rm -rf "$tmpd"
    return 1
  fi
  rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"
  if ! jq -n \
    --slurpfile prefs "$merged_prefs" \
    --slurpfile repos "${FILESYNC_REPOS_FILE}" \
    --argjson files '[]' \
    --arg rroot "$rroot" \
    '$prefs[0] * {repos: $repos[0], files: $files, repo_path_root: $rroot}' > "$out"; then
    rm -rf "$tmpd"
    return 1
  fi
  rm -rf "$tmpd"
}
