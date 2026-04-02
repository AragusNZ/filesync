#!/usr/bin/env bash
# Shared CLI banners, filter context, and common messages (stderr).
# Requires lib/colors.sh.

# shellcheck disable=SC2154

filesync_print_disabled_hint() {
  echo -e "${YELLOW}filesync is disabled. Run 'filesync enable' to enable.${NC}" >&2
}

filesync_print_sync_banner() {
  echo -e "${BOLD}${WHITE}Syncing files from repo(s)...${NC}" >&2
}

filesync_print_check_banner() {
  echo -e "${BOLD}${WHITE}Checking synced files (updating .filesync)...${NC}" >&2
}

filesync_print_filter_note() {
  echo -e "${GRAY}---- $1 ----${NC}" >&2
}

# Args: repo_filter file_fragment status_csv include_detached [is_sync] [force]
# When is_sync is 1 and status_csv is empty, prints sync default status mode line.
filesync_print_filter_context() {
  local repo="${1:-}" frag="${2:-}" status_csv="${3:-}" inc_det="${4:-false}" is_sync="${5:-0}" force="${6:-false}"
  if [[ -n "$repo" ]]; then
    filesync_print_filter_note "Filter: --repo=$repo"
  fi
  if [[ -n "$frag" ]]; then
    filesync_print_filter_note "Filter: --file= substring on local_path or repo_file_path: ${frag}"
  fi
  if [[ -n "$status_csv" ]]; then
    filesync_print_filter_note "Filter: --status=${status_csv}"
  elif [[ "$is_sync" == 1 ]]; then
    filesync_print_filter_note "Mode: unset or sync_required only (use --status=a,b,... to include other statuses)"
    if [[ "$force" == true ]]; then
      filesync_print_filter_note "Also: -f/--force additionally selects local_newer and conflict (overwrite from master)"
    fi
  fi
  if [[ "$inc_det" == true ]]; then
    filesync_print_filter_note "Also: --include-detached"
  fi
}

filesync_print_sync_showall_banner() {
  if [[ "${1:-false}" == true ]]; then
    filesync_print_filter_note "Also: --showall (per-file already-in-sync lines)"
  fi
}

filesync_print_section_title() {
  echo -e "${BOLD}${WHITE}$1...${NC}" >&2
}

filesync_print_list_files_heading() {
  echo -e "${BOLD}${WHITE}Listing files (run FILESYNC check to refresh status)...${NC}" >&2
}

filesync_print_no_file_rows_for_fragment() {
  echo -e "${YELLOW}No file rows matched --file=$1${NC} (and repo filter if any)." >&2
}

filesync_print_no_file_rows_for_status() {
  echo -e "${YELLOW}No file rows matched --status=$1${NC} (and other filters if any)." >&2
}

filesync_print_config_error_invalid_repo_name() {
  echo -e "${RED}✗${NC} ${WHITE}Entry $1: Invalid repo_name${NC} ${RED}[config]${NC}" >&2
}

filesync_print_config_error_invalid_local_path() {
  echo -e "${RED}✗${NC} ${WHITE}Entry $1: Invalid local_path${NC} ${RED}[config]${NC}" >&2
}

filesync_print_config_error_invalid_repo_file_path() {
  echo -e "${RED}✗${NC} ${WHITE}$1: Invalid repo_file_path${NC} ${RED}[config]${NC}" >&2
}
