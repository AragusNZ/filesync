#!/usr/bin/env bash
# Resolve scripts directory from merged state JSON (requires jq, CONFIG_FILE).

# Sets SCRIPTS_DIR from CONFIG_FILE (default .scripts).
filesync_scripts_dir_from_state_config() {
  local config_path="${CONFIG_FILE:?}"
  local fallback=".scripts"
  SCRIPTS_DIR="$fallback"
  local val
  val=$(jq -r '.scripts_local_directory // .scripts_repo_directory // ""' "$config_path" 2>/dev/null)
  if [[ -n "$val" ]] && [[ "$val" != "null" ]]; then
    SCRIPTS_DIR="$val"
  fi
  SCRIPTS_DIR="${SCRIPTS_DIR:-$fallback}"
  export SCRIPTS_DIR
}
