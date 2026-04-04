#!/usr/bin/env bash
# Shared CLI banners, filter context, and common messages (stderr).
# Requires lib/colors.sh.

# shellcheck disable=SC2154

filesync_print_disabled_hint() {
  echo -e "${YELLOW}No file rows to check or sync (repos may have check_sync_enabled false). Use 'filesync config' to inspect or change repo flags.${NC}" >&2
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

# Args: repo_filter local_label repo_file_label all_files_label status_csv include_detached [is_sync] [force]
# When is_sync is 1 and status_csv is empty, prints sync default status mode line.
filesync_print_filter_context() {
  local repo="${1:-}" loc="${2:-}" rfp="${3:-}" allf="${4:-}" status_csv="${5:-}" inc_det="${6:-false}" is_sync="${7:-0}" force="${8:-false}"
  if [[ -n "$repo" ]]; then
    filesync_print_filter_note "Filter: --repo=$repo"
  fi
  if [[ -n "$loc" ]]; then
    filesync_print_filter_note "Filter: --file= substring on local_path: ${loc}"
  fi
  if [[ -n "$rfp" ]]; then
    filesync_print_filter_note "Filter: --repo-file= substring on repo_file_path: ${rfp}"
  fi
  if [[ -n "$allf" ]]; then
    filesync_print_filter_note "Filter: --all-files= substring on local_path or repo_file_path: ${allf}"
  fi
  if [[ -n "$status_csv" ]]; then
    filesync_print_filter_note "Filter: --status=${status_csv}"
  elif [[ "$is_sync" == 1 ]]; then
    filesync_print_filter_note "Mode: unset, sync_required, error_missing_local, master_file_moved (use --status=a,b,... to include other statuses)"
    if [[ "$force" == true ]]; then
      filesync_print_filter_note "Also: -f/--force additionally selects local_newer and conflict (overwrite from master)"
    fi
  fi
  if [[ "$inc_det" == true ]]; then
    filesync_print_filter_note "Also: --include-detached"
  fi
}

filesync_print_section_title() {
  echo -e "${BOLD}${WHITE}$1...${NC}" >&2
}

# Section heading for info commands (stderr): blank line, title, gray rule.
filesync_print_info_heading() {
  local title="$1"
  local ulen="${#title}"
  echo "" >&2
  echo -e "  ${BOLD}${WHITE}${title}${NC}" >&2
  if [[ "$ulen" -gt 0 ]]; then
    printf '  %b' "${GRAY}" >&2
    local i
    for ((i = 0; i < ulen; i++)); do
      printf '─'
    done
    printf '%b\n' "${NC}" >&2
  fi
}

# One "label: value" line for info output (stderr).
filesync_print_info_kv() {
  printf '  %b%s:%b %s\n' "${GRAY}" "$1" "${NC}" "$2" >&2
}

filesync_print_list_files_heading() {
  echo -e "${BOLD}${WHITE}Listing files (run FILESYNC check to refresh status)...${NC}" >&2
}

filesync_print_no_file_rows_for_fragment() {
  echo -e "${YELLOW}No file rows matched --file=$1${NC} (and repo filter if any)." >&2
}

# Args: optional local_path fragment label, repo_file_path fragment label, --all-files label (empty skips).
filesync_print_no_file_rows_path_filters() {
  local loc="${1:-}" rfp="${2:-}" allf="${3:-}"
  local parts=()
  [[ -n "$loc" ]] && parts+=("--file=: ${loc}")
  [[ -n "$rfp" ]] && parts+=("--repo-file=: ${rfp}")
  [[ -n "$allf" ]] && parts+=("--all-files=: ${allf}")
  [[ ${#parts[@]} -eq 0 ]] && return 0
  local joined
  joined=$(IFS='; '; echo "${parts[*]}")
  echo -e "${YELLOW}No file rows matched path filter(s): ${joined}${NC} (and repo filter if any)." >&2
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
