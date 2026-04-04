#!/usr/bin/env bash
# Usage: list.sh repos | files | collections (first argv; invoked via filesync list …).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"

FILESYNC_LIST_REPOS_LINE='filesync list repos [--repo=name]'
FILESYNC_LIST_FILES_LINE='filesync list files [options]'
FILESYNC_LIST_COLLECTIONS_LINE='filesync list collections'
FILESYNC_LIST_REPOS_USAGE="Usage: ${FILESYNC_LIST_REPOS_LINE}"
FILESYNC_LIST_FILES_USAGE="Usage: ${FILESYNC_LIST_FILES_LINE}"
FILESYNC_LIST_COLLECTIONS_USAGE="Usage: ${FILESYNC_LIST_COLLECTIONS_LINE}"
FILESYNC_CMD_USAGE="Usage: ${FILESYNC_LIST_REPOS_LINE} | filesync list files [--repo=name] [--file=...] [--repo-file=...] [--all-files=...] [--status=a,b,...] [--include-detached] | ${FILESYNC_LIST_COLLECTIONS_LINE}"

sub="${1:-}"
if filesync_argv_wants_help "$@"; then
  case "$sub" in
    repos)
      cat <<EOF
${FILESYNC_LIST_REPOS_USAGE}
Also: l -r

List repos from the shared store. With --repo=, show only that repo (errors if it is missing).
No project .filesync/ needed.
EOF
      ;;
    files)
      cat <<EOF
${FILESYNC_LIST_FILES_USAGE}
Also: l, l -f

List tracked files and their status. Requires a project (walk-up .filesync/ for files.json).
Path filters work like sync/check: --file (local path), --repo-file (path in repo), --all-files (either);
repeat a flag for OR within that kind; combine kinds with AND.
--status uses the same tokens as sync/check (filesync -h or man filesync).
EOF
      ;;
    collections)
      cat <<EOF
${FILESYNC_LIST_COLLECTIONS_USAGE}
Also: l -col

List named repo groups from the shared store (for use with --also= when adding files).
No project .filesync/ needed.
EOF
      ;;
    *)
      cat <<EOF
Usage:
  ${FILESYNC_LIST_REPOS_LINE}
  ${FILESYNC_LIST_FILES_LINE}
  ${FILESYNC_LIST_COLLECTIONS_LINE}

Shorthand: l -r | l | l -f | l -col

Run filesync list repos -h, list files -h, or list collections -h for more detail.
EOF
      ;;
  esac
  exit 0
fi

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"

if [[ -z "$sub" ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi
shift

REPO_FILTER=""
declare -a FILE_FRAGMENTS=()
declare -a REPO_FILE_FRAGMENTS=()
declare -a ALL_FILES_FRAGMENTS=()
STATUS_CSV=""
INCLUDE_DETACHED=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo=*)
      REPO_FILTER="${1#*=}"
      shift
      ;;
    --file=*)
      FILE_FRAGMENTS+=("${1#*=}")
      shift
      ;;
    --repo-file=*)
      REPO_FILE_FRAGMENTS+=("${1#*=}")
      shift
      ;;
    --all-files=*)
      ALL_FILES_FRAGMENTS+=("${1#*=}")
      shift
      ;;
    --include-detached)
      INCLUDE_DETACHED=true
      shift
      ;;
    --status=*)
      STATUS_CSV="${1#*=}"
      shift
      ;;
    -*)
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
  esac
done

case "$sub" in
  repos) ;;
  files) ;;
  collections) ;;
  *)
    filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
    exit 1
    ;;
esac

if [[ "$sub" == repos ]] && { [[ ${#FILE_FRAGMENTS[@]} -gt 0 ]] || [[ ${#REPO_FILE_FRAGMENTS[@]} -gt 0 ]] || [[ ${#ALL_FILES_FRAGMENTS[@]} -gt 0 ]]; }; then
  echo -e "${RED}filesync list repos does not accept path filters (--file, --repo-file, --all-files)${NC}" >&2
  filesync_usage_error_stderr "$FILESYNC_LIST_REPOS_USAGE"
  exit 1
fi

if [[ "$sub" == repos ]] && [[ -n "$STATUS_CSV" ]]; then
  echo -e "${RED}filesync list repos does not accept --status${NC}" >&2
  filesync_usage_error_stderr "$FILESYNC_LIST_REPOS_USAGE"
  exit 1
fi

if [[ "$sub" == repos ]] && [[ "$INCLUDE_DETACHED" == true ]]; then
  echo -e "${RED}filesync list repos does not accept --include-detached${NC}" >&2
  filesync_usage_error_stderr "$FILESYNC_LIST_REPOS_USAGE"
  exit 1
fi

if [[ "$sub" == collections ]]; then
  if [[ -n "$REPO_FILTER" ]]; then
    echo -e "${RED}filesync list collections does not accept --repo${NC}" >&2
    filesync_usage_error_stderr "$FILESYNC_LIST_COLLECTIONS_USAGE"
    exit 1
  fi
  if [[ ${#FILE_FRAGMENTS[@]} -gt 0 ]] || [[ ${#REPO_FILE_FRAGMENTS[@]} -gt 0 ]] || [[ ${#ALL_FILES_FRAGMENTS[@]} -gt 0 ]]; then
    echo -e "${RED}filesync list collections does not accept path filters (--file, --repo-file, --all-files)${NC}" >&2
    filesync_usage_error_stderr "$FILESYNC_LIST_COLLECTIONS_USAGE"
    exit 1
  fi
  if [[ -n "$STATUS_CSV" ]]; then
    echo -e "${RED}filesync list collections does not accept --status${NC}" >&2
    filesync_usage_error_stderr "$FILESYNC_LIST_COLLECTIONS_USAGE"
    exit 1
  fi
  if [[ "$INCLUDE_DETACHED" == true ]]; then
    echo -e "${RED}filesync list collections does not accept --include-detached${NC}" >&2
    filesync_usage_error_stderr "$FILESYNC_LIST_COLLECTIONS_USAGE"
    exit 1
  fi
fi

case "$sub" in
  files)
    filesync_command_init "${BASH_SOURCE[0]}"
    ;;
  repos|collections)
    filesync_command_init_system "${BASH_SOURCE[0]}"
    # shellcheck source=/dev/null
    source "$_CMD_ROOT/../lib/json-state.sh"
    FILESYNC_STATE_FILE=$(mktemp)
    filesync_assemble_global_catalog_state_to "$FILESYNC_STATE_FILE" || exit 1
    CONFIG_FILE="$FILESYNC_STATE_FILE"
    export CONFIG_FILE FILESYNC_STATE_FILE
    ;;
esac

# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-banner.sh"
trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

case "$sub" in
  repos)
    filesync_print_section_title "Repos"
    if [[ -n "$REPO_FILTER" ]]; then
      filesync_print_filter_note "Filter: --repo=$REPO_FILTER"
    fi
    if [[ -n "$REPO_FILTER" ]]; then
      found=$(jq -e --arg n "$REPO_FILTER" '.repos[] | select(.name == $n)' "$CONFIG_FILE" 2>/dev/null || true)
      if [[ -z "$found" ]]; then
        echo -e "${RED}No repo named '$REPO_FILTER'${NC}" >&2
        exit 1
      fi
      jq -r --arg n "$REPO_FILTER" '.repos[] | select(.name == $n) | "name:   \(.name)\nurl:    \(.url)\npath:   \(.path)\nbranch: \(.branch)\n"' "$CONFIG_FILE"
    else
      jq -r '.repos[] | "\(.name)\n  url: \(.url)\n  path: \(.path)\n  branch: \(.branch)\n"' "$CONFIG_FILE"
    fi
    ;;
  files)
    filesync_print_list_files_heading
    FILE_FILTER_LABEL=""
    if [[ ${#FILE_FRAGMENTS[@]} -gt 0 ]]; then
      mapfile -t _lf_nf < <(filesync_emit_nonempty_file_fragments FILE_FRAGMENTS)
      [[ ${#_lf_nf[@]} -gt 0 ]] && FILE_FILTER_LABEL=$(IFS=', '; echo "${_lf_nf[*]}")
    fi
    REPO_FILE_FILTER_LABEL=""
    if [[ ${#REPO_FILE_FRAGMENTS[@]} -gt 0 ]]; then
      mapfile -t _rf_nf < <(filesync_emit_nonempty_file_fragments REPO_FILE_FRAGMENTS)
      [[ ${#_rf_nf[@]} -gt 0 ]] && REPO_FILE_FILTER_LABEL=$(IFS=', '; echo "${_rf_nf[*]}")
    fi
    ALL_FILES_FILTER_LABEL=""
    if [[ ${#ALL_FILES_FRAGMENTS[@]} -gt 0 ]]; then
      mapfile -t _af_nf < <(filesync_emit_nonempty_file_fragments ALL_FILES_FRAGMENTS)
      [[ ${#_af_nf[@]} -gt 0 ]] && ALL_FILES_FILTER_LABEL=$(IFS=', '; echo "${_af_nf[*]}")
    fi
    filesync_print_filter_context "$REPO_FILTER" "$FILE_FILTER_LABEL" "$REPO_FILE_FILTER_LABEL" "$ALL_FILES_FILTER_LABEL" "$STATUS_CSV" "$INCLUDE_DETACHED" 0
    # shellcheck disable=SC2034  # Used via nameref in filesync_counts_inc/render helpers.
    declare -A LIST_STATUS_COUNTS=()
    print_file_line() {
      file_sync_print_file_row "$1" "$2" "$3" "${4:-unset}" "${5:-}"
    }
    if [[ -n "$REPO_FILTER" ]]; then
      count=$(jq --arg n "$REPO_FILTER" '[.files[] | select(.repo_name == $n)] | length' "$CONFIG_FILE")
      if [[ "$count" -eq 0 ]]; then
        echo -e "${RED}No files for repo '$REPO_FILTER'${NC}" >&2
        exit 1
      fi
      TOTAL_FOR_LIST=$count
    else
      TOTAL_FOR_LIST=$(jq '.files | length' "$CONFIG_FILE")
    fi
    printed=0
    if [[ -n "$REPO_FILTER" ]]; then
      while IFS=$'\t' read -r rn rp lp st mw; do
        filesync_row_matches_path_filter_groups "$lp" "$rp" FILE_FRAGMENTS REPO_FILE_FRAGMENTS ALL_FILES_FRAGMENTS || continue
        if [[ -n "$STATUS_CSV" ]] && ! file_sync_status_matches_csv "$st" "$STATUS_CSV" "$INCLUDE_DETACHED"; then
          continue
        fi
        print_file_line "$rn" "$rp" "$lp" "$st" "$mw"
        printed=$((printed + 1))
        filesync_counts_inc LIST_STATUS_COUNTS "${st:-unset}"
      done < <(jq -r --arg n "$REPO_FILTER" '.files[] | select(.repo_name == $n) | "\(.repo_name)\t\(.repo_file_path)\t\(.local_path)\t\(.sync_status // "")\t\(.check_marker_warnings // [] | join(","))"' "$CONFIG_FILE")
    else
      while IFS=$'\t' read -r rn rp lp st mw; do
        filesync_row_matches_path_filter_groups "$lp" "$rp" FILE_FRAGMENTS REPO_FILE_FRAGMENTS ALL_FILES_FRAGMENTS || continue
        if [[ -n "$STATUS_CSV" ]] && ! file_sync_status_matches_csv "$st" "$STATUS_CSV" "$INCLUDE_DETACHED"; then
          continue
        fi
        print_file_line "$rn" "$rp" "$lp" "$st" "$mw"
        printed=$((printed + 1))
        filesync_counts_inc LIST_STATUS_COUNTS "${st:-unset}"
      done < <(jq -r '.files[] | "\(.repo_name)\t\(.repo_file_path)\t\(.local_path)\t\(.sync_status // "")\t\(.check_marker_warnings // [] | join(","))"' "$CONFIG_FILE")
    fi
    if [[ "$printed" -eq 0 ]] && [[ "$TOTAL_FOR_LIST" -gt 0 ]] && { [[ -n "$FILE_FILTER_LABEL" ]] || [[ -n "$REPO_FILE_FILTER_LABEL" ]] || [[ -n "$ALL_FILES_FILTER_LABEL" ]]; }; then
      filesync_print_no_file_rows_path_filters "$FILE_FILTER_LABEL" "$REPO_FILE_FILTER_LABEL" "$ALL_FILES_FILTER_LABEL"
    fi
    if [[ -n "$STATUS_CSV" ]] && [[ "$printed" -eq 0 ]] && [[ "$TOTAL_FOR_LIST" -gt 0 ]]; then
      filesync_print_no_file_rows_for_status "$STATUS_CSV"
    fi
    if [[ "$printed" -gt 0 ]]; then
      filesync_print_status_summary "rows listed" "$printed" LIST_STATUS_COUNTS
    fi
    ;;
  collections)
    filesync_print_section_title "Collections"
    if [[ ! -f "$FILESYNC_COLLECTIONS_FILE" ]]; then
      echo "(no collections.json)" >&2
      exit 0
    fi
    if ! jq -e 'type == "array"' "$FILESYNC_COLLECTIONS_FILE" &>/dev/null; then
      echo -e "${RED}Invalid collections.json (expected JSON array)${NC}" >&2
      exit 1
    fi
    if [[ "$(jq 'length' "$FILESYNC_COLLECTIONS_FILE")" -eq 0 ]]; then
      echo "(no collections defined)" >&2
      exit 0
    fi
    jq -r '.[] | "\(.name)\n  repos: \(.repos // [] | join(", "))\n"' "$FILESYNC_COLLECTIONS_FILE"
    ;;
esac
