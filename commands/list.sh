#!/usr/bin/env bash
# Usage: list.sh repos [--repo=name] | list.sh list [--repo=name] [--file=path_fragment]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

sub="${1:-}"
if [[ -z "$sub" ]]; then
  echo -e "${RED}Usage: filesync repos [--repo=name] | filesync list [--repo=name] [--file=path_fragment]${NC}"
  exit 1
fi
shift

REPO_FILTER=""
FILE_FRAGMENT=""
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
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync repos [--repo=name] | filesync list [--repo=name] [--file=path_fragment]" >&2
      exit 1
      ;;
    *)
      echo -e "${RED}Unexpected argument: $1${NC}" >&2
      echo "Usage: filesync repos [--repo=name] | filesync list [--repo=name] [--file=path_fragment]" >&2
      exit 1
      ;;
  esac
done

if [[ "$sub" == "repos" && -n "$FILE_FRAGMENT" ]]; then
  echo -e "${RED}filesync repos does not accept --file${NC}" >&2
  echo "Usage: filesync repos [--repo=name]" >&2
  exit 1
fi

case "$sub" in
  repos)
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
  list)
    echo -e "${CYAN}Files${NC} (run ${YELLOW}filesync check${CYAN} to refresh status)"
    echo "------"
    [[ -n "$REPO_FILTER" ]] && echo -e "${CYAN}Filter: --repo=$REPO_FILTER${NC}"
    [[ -n "$FILE_FRAGMENT" ]] && echo -e "${CYAN}Filter: --file= substring on local_path or repo_file_path: ${FILE_FRAGMENT}${NC}"
    print_file_line() {
      local rn="$1" rp="$2" lp="$3" st="${4:-}"
      local st_disp
      if [[ -t 1 ]]; then
        st_disp="$(printf '%b%s%b' "$(file_sync_status_color "${st:-unset}")" "${st:-unset}" "$(file_sync_color_reset)")"
      else
        st_disp="${st:-unset}"
      fi
      if [[ "$rp" == "$lp" ]]; then
        echo -e "[$st_disp] $rn | $rp"
      else
        echo -e "[$st_disp] $rn | $rp -> ${YELLOW}$lp${NC}"
      fi
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
      while IFS=$'\t' read -r rn rp lp st; do
        filesync_file_matches_fragment "$FILE_FRAGMENT" "$lp" "$rp" || continue
        print_file_line "$rn" "$rp" "$lp" "$st"
        printed=$((printed + 1))
      done < <(jq -r --arg n "$REPO_FILTER" '.files[] | select(.repo_name == $n) | "\(.repo_name)\t\(.repo_file_path)\t\(.local_path)\t\(.sync_status // "")"' "$CONFIG_FILE")
    else
      while IFS=$'\t' read -r rn rp lp st; do
        filesync_file_matches_fragment "$FILE_FRAGMENT" "$lp" "$rp" || continue
        print_file_line "$rn" "$rp" "$lp" "$st"
        printed=$((printed + 1))
      done < <(jq -r '.files[] | "\(.repo_name)\t\(.repo_file_path)\t\(.local_path)\t\(.sync_status // "")"' "$CONFIG_FILE")
    fi
    if [[ -n "$FILE_FRAGMENT" ]] && [[ "$printed" -eq 0 ]] && [[ "$TOTAL_FOR_LIST" -gt 0 ]]; then
      echo -e "${YELLOW}No file rows matched --file=${FILE_FRAGMENT}${NC} (and repo filter if any)."
    fi
    ;;
  *)
    echo -e "${RED}Usage: filesync repos [--repo=name] | filesync list [--repo=name] [--file=path_fragment]${NC}"
    exit 1
    ;;
esac
