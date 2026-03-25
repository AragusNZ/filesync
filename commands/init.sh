#!/usr/bin/env bash
# Create .filesync/ with config.json, repos.json, files.json at the project root (cwd or path).
# Does not walk parents — the given directory (default: cwd) becomes the filesync project root.
# Usage: filesync init [directory]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILESYNC_PKG_ROOT="$(cd "${_CMD_ROOT}/.." && pwd)"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/data-names.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/deps.sh"

filesync_require_jq

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync init [directory]" >&2
      exit 1
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        echo -e "${RED}Too many arguments${NC}" >&2
        echo "Usage: filesync init [directory]" >&2
        exit 1
      fi
      TARGET="$1"
      shift
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  PROJECT_ROOT="$(pwd -P)"
else
  if [[ ! -d "$TARGET" ]]; then
    echo -e "${RED}filesync: not a directory: ${TARGET}${NC}" >&2
    exit 1
  fi
  PROJECT_ROOT="$(cd "$TARGET" && pwd -P)"
fi

FILESYNC_DIR="${PROJECT_ROOT}/.filesync"
DEFAULT_CFG="${FILESYNC_PKG_ROOT}/share/defaults/config.default.json"

cfg="${FILESYNC_DIR}/${FILESYNC_CONFIG_NAME}"
repos="${FILESYNC_DIR}/${FILESYNC_REPOS_NAME}"
files="${FILESYNC_DIR}/${FILESYNC_FILES_NAME}"

if [[ -f "$cfg" && -f "$repos" && -f "$files" ]]; then
  echo -e "${YELLOW}filesync: already initialized at ${FILESYNC_DIR}${NC}" >&2
  exit 1
fi

mkdir -p "$FILESYNC_DIR"

if [[ ! -f "$cfg" ]]; then
  if [[ -f "$DEFAULT_CFG" ]]; then
    cp "$DEFAULT_CFG" "$cfg"
  else
    echo '{"file_sync_enabled":true,"path_mode":"relative"}' | jq . > "$cfg"
  fi
fi

if [[ ! -f "$repos" ]]; then
  printf '%s\n' '[]' | jq . > "$repos"
fi

if [[ ! -f "$files" ]]; then
  printf '%s\n' '[]' | jq . > "$files"
fi

echo -e "${GREEN}filesync: initialized project root${NC} ${PROJECT_ROOT}"
echo "  ${FILESYNC_DIR}/"
