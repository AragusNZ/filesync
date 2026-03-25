#!/usr/bin/env bash
# Usage: list.sh list-repos [--repo=name] | list.sh list-files [--repo=name] [--file=path_fragment] [--status=a,b,...] [--include-detached]
# Dispatcher passes longform mode; repos|lr and list|lf are accepted for compatibility.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

_list_usage_pair='filesync list-repos [--repo=name] | filesync list-files [--repo=name] [--file=path_fragment] [--status=a,b,...] [--include-detached]'

sub="${1:-}"
if [[ -z "$sub" ]]; then
  echo -e "${RED}Usage: ${_list_usage_pair}${NC}"
  exit 1
fi
shift

REPO_FILTER=""
FILE_FRAGMENT=""
STATUS_CSV=""
INCLUDE_DETACHED=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo=*)
      REPO_FILTER="${1#*=}"
      shift
      ;;
    --file=*)
      FILE_FRAGMENT="${1#*=}"
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
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: ${_list_usage_pair}" >&2
      exit 1
      ;;
    *)
      echo -e "${RED}Unexpected argument: $1${NC}" >&2
      echo "Usage: ${_list_usage_pair}" >&2
      exit 1
      ;;
  esac
done

case "$sub" in
  list-repos|repos|lr) ;;
  list-files|list|lf|files) ;;
  *)
    echo -e "${RED}Usage: ${_list_usage_pair}${NC}"
    exit 1
    ;;
esac

if [[ "$sub" == list-repos || "$sub" == repos || "$sub" == lr ]] && [[ -n "$FILE_FRAGMENT" ]]; then
  echo -e "${RED}filesync list-repos does not accept --file${NC}" >&2
  echo "Usage: filesync list-repos [--repo=name]" >&2
  exit 1
fi

if [[ "$sub" == list-repos || "$sub" == repos || "$sub" == lr ]] && [[ -n "$STATUS_CSV" ]]; then
  echo -e "${RED}filesync list-repos does not accept --status${NC}" >&2
  echo "Usage: filesync list-repos [--repo=name]" >&2
  exit 1
fi

if [[ "$sub" == list-repos || "$sub" == repos || "$sub" == lr ]] && [[ "$INCLUDE_DETACHED" == true ]]; then
  echo -e "${RED}filesync list-repos does not accept --include-detached${NC}" >&2
  echo "Usage: filesync list-repos [--repo=name]" >&2
  exit 1
fi

case "$sub" in
  list-repos|repos|lr)
    echo -e "${CYAN}Repos${NC}"
    echo "------"
    [[ -n "$REPO_FILTER" ]] && echo -e "${CYAN}Filter: --repo=$REPO_FILTER${NC}"
    if [[ -n "$REPO_FILTER" ]]; then
      found=$(jq -e --arg n "$REPO_FILTER" '.repos[] | select(.name == $n)' "$CONFIG_FILE" 2>/dev/null || true)
      if [[ -z "$found" ]]; then
        echo -e "${RED}No repo named '$REPO_FILTER'${NC}"
        exit 1
      fi
      jq -r --arg n "$REPO_FILTER" '.repos[] | select(.name == $n) | "name:   \(.name)\nurl:    \(.url)\npath:   \(.path)\nbranch: \(.branch)\n"' "$CONFIG_FILE"
    else
      jq -r '.repos[] | "\(.name)\n  url: \(.url)\n  path: \(.path)\n  branch: \(.branch)\n"' "$CONFIG_FILE"
    fi
    ;;
  list-files|list|lf|files)
    echo -e "${CYAN}Files${NC} (run ${YELLOW}filesync check${CYAN} to refresh status)"
    echo "------"
    [[ -n "$REPO_FILTER" ]] && echo -e "${CYAN}Filter: --repo=$REPO_FILTER${NC}"
    [[ -n "$FILE_FRAGMENT" ]] && echo -e "${CYAN}Filter: --file= substring on local_path or repo_file_path: ${FILE_FRAGMENT}${NC}"
    [[ -n "$STATUS_CSV" ]] && echo -e "${CYAN}Filter: --status=${STATUS_CSV}${NC}"
    [[ "$INCLUDE_DETACHED" == true ]] && echo -e "${CYAN}Also: --include-detached${NC}"
    print_file_line() {
      file_sync_print_file_row "$1" "$2" "$3" "${4:-unset}" "${5:-}"
    }
    if [[ -n "$REPO_FILTER" ]]; then
      count=$(jq --arg n "$REPO_FILTER" '[.files[] | select(.repo_name == $n)] | length' "$CONFIG_FILE")
      if [[ "$count" -eq 0 ]]; then
        echo -e "${RED}No files for repo '$REPO_FILTER'${NC}"
        exit 1
      fi
      TOTAL_FOR_LIST=$count
    else
      TOTAL_FOR_LIST=$(jq '.files | length' "$CONFIG_FILE")
    fi
    printed=0
    if [[ -n "$REPO_FILTER" ]]; then
      while IFS=$'\t' read -r rn rp lp st mw; do
        filesync_file_matches_fragment "$FILE_FRAGMENT" "$lp" "$rp" || continue
        if [[ -n "$STATUS_CSV" ]] && ! file_sync_status_matches_csv "$st" "$STATUS_CSV" "$INCLUDE_DETACHED"; then
          continue
        fi
        print_file_line "$rn" "$rp" "$lp" "$st" "$mw"
        printed=$((printed + 1))
      done < <(jq -r --arg n "$REPO_FILTER" '.files[] | select(.repo_name == $n) | "\(.repo_name)\t\(.repo_file_path)\t\(.local_path)\t\(.sync_status // "")\t\(.check_marker_warnings // [] | join(","))"' "$CONFIG_FILE")
    else
      while IFS=$'\t' read -r rn rp lp st mw; do
        filesync_file_matches_fragment "$FILE_FRAGMENT" "$lp" "$rp" || continue
        if [[ -n "$STATUS_CSV" ]] && ! file_sync_status_matches_csv "$st" "$STATUS_CSV" "$INCLUDE_DETACHED"; then
          continue
        fi
        print_file_line "$rn" "$rp" "$lp" "$st" "$mw"
        printed=$((printed + 1))
      done < <(jq -r '.files[] | "\(.repo_name)\t\(.repo_file_path)\t\(.local_path)\t\(.sync_status // "")\t\(.check_marker_warnings // [] | join(","))"' "$CONFIG_FILE")
    fi
    if [[ -n "$FILE_FRAGMENT" ]] && [[ "$printed" -eq 0 ]] && [[ "$TOTAL_FOR_LIST" -gt 0 ]]; then
      echo -e "${YELLOW}No file rows matched --file=${FILE_FRAGMENT}${NC} (and repo filter if any)."
    fi
    if [[ -n "$STATUS_CSV" ]] && [[ "$printed" -eq 0 ]] && [[ "$TOTAL_FOR_LIST" -gt 0 ]]; then
      echo -e "${YELLOW}No file rows matched --status=${STATUS_CSV}${NC} (and other filters if any)."
    fi
    ;;
esac
