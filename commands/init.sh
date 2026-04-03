#!/usr/bin/env bash
# Create .filesync/files.json at the project root (cwd or path) and ensure system-level store.
# Usage: filesync init [directory] [--no-repo]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILESYNC_PKG_ROOT="$(cd "${_CMD_ROOT}/.." && pwd)"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync init [directory] [--no-repo]

Create .filesync/files.json at the project root (default: current working directory).
Also ensures the system filesync store exists (default ~/.filesync-root; FILESYNC_HOME overrides) with repos and collections.

When stdin is a terminal and --no-repo is not passed, prompts to add a repo entry to the global
repos.json (name, URL, branch). The checkout path (relative to home when possible) is derived from this
project directory (git work tree top when inside git, otherwise the project root). If the project
is inside a git work tree, defaults are also taken from git for name, remote URL, and branch.

Does not walk parent directories: the given directory becomes the filesync project root.

If files.json already exists, init exits with an error.

  --no-repo   Skip registering a global repo (non-interactive scripts and CI).

If stdin is not a terminal, global repo registration is skipped; use new repo (n -r) later, or run init
from a terminal, or pass --no-repo to silence the notice.
EOF
  exit 0
fi
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/log.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/data-names.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/deps.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/system-resolve.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/collections.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/paths.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/git-repo-hints.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/repo-id.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/fs-lock.sh"

filesync_require_jq

TARGET=""
SKIP_GLOBAL_REPO=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-repo)
      SKIP_GLOBAL_REPO=1
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      echo "Usage: filesync init [directory] [--no-repo]" >&2
      exit 1
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        echo -e "${RED}Too many arguments${NC}" >&2
        echo "Usage: filesync init [directory] [--no-repo]" >&2
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
files="${FILESYNC_DIR}/${FILESYNC_FILES_NAME}"

if [[ -f "$files" ]]; then
  echo -e "${YELLOW}filesync: already initialized at ${FILESYNC_DIR}${NC}" >&2
  exit 1
fi

mkdir -p "$FILESYNC_DIR"
printf '%s\n' '[]' | jq . >"$files"

FILESYNC_SYSTEM_HOME="$(filesync_ensure_system_store)" || exit 1
echo -e "${GREEN}filesync: initialized project root${NC} ${PROJECT_ROOT}" >&2
echo "  ${FILESYNC_DIR}/files.json" >&2
echo -e "${GRAY}System store:${NC} ${FILESYNC_SYSTEM_HOME}" >&2

if [[ "$SKIP_GLOBAL_REPO" -eq 1 ]]; then
  exit 0
fi

if [[ ! -t 0 ]]; then
  echo -e "${GRAY}filesync: no terminal on stdin; skipped global repos.json entry (use ${BOLD}filesync new repo${NC}${GRAY}).${NC}" >&2
  exit 0
fi

repos="${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"
coll="${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_COLLECTIONS_NAME}"
rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"
if [[ -z "$rroot" || "$rroot" == "null" ]]; then
  echo -e "${RED}filesync: could not resolve path anchor (HOME)${NC}" >&2
  exit 1
fi

filesync_git_collect_hints "$PROJECT_ROOT"
def_name="$(basename "${FILESYNC_GIT_HINT_TOP:-$PROJECT_ROOT}")"
def_checkout="${FILESYNC_GIT_HINT_TOP:-$PROJECT_ROOT}"
path="$(filesync_path_for_repos_json "$rroot" "$def_checkout")"
if [[ -z "$path" ]]; then
  echo -e "${RED}filesync: could not derive checkout path (home=${rroot}, checkout=${def_checkout})${NC}" >&2
  exit 1
fi
def_url="${FILESYNC_GIT_HINT_URL:-}"
def_branch="${FILESYNC_GIT_HINT_BRANCH:-main}"

echo "" >&2
echo -e "${BOLD}${WHITE}Register this project in global ${FILESYNC_GLOBAL_REPOS_NAME}${NC}" >&2
if [[ -n "$FILESYNC_GIT_HINT_TOP" ]]; then
  echo -e "${GRAY}(defaults from git work tree: ${FILESYNC_GIT_HINT_TOP})${NC}" >&2
fi
echo -e "${GRAY}Checkout path (relative to home when possible): ${path}${NC}" >&2
echo "" >&2

read -rp "Repo name [${def_name}]: " name
name="${name:-$def_name}"
name="${name#"${name%%[![:space:]]*}"}"
name="${name%"${name##*[![:space:]]}"}"
if [[ -z "$name" ]]; then
  echo -e "${YELLOW}Skipped global repo entry.${NC}" >&2
  exit 0
fi

if jq -e --arg n "$name" 'any(.name == $n)' "$repos" &>/dev/null; then
  echo -e "${RED}Error: Repo '$name' already exists in global repos.${NC}" >&2
  exit 1
fi
if [[ -f "$coll" ]] && filesync_collections_name_taken "$coll" "$name"; then
  echo -e "${RED}Error: '$name' is already a collection name; repo names must be distinct from collection names.${NC}" >&2
  exit 1
fi

if [[ -n "$def_url" ]]; then
  read -rp "Remote URL [${def_url}]: " url
  url="${url:-$def_url}"
else
  read -rp "Remote URL (e.g. https://github.com/org/repo): " url
fi

read -rp "Branch [${def_branch}]: " branch
branch="${branch:-$def_branch}"

rid="$(filesync_new_repo_id)"
NEW_ENTRY=$(jq -n \
  --arg id "$rid" \
  --arg name "$name" \
  --arg url "$url" \
  --arg path "$path" \
  --arg branch "$branch" \
  '{id: $id, name: $name, url: $url, path: $path, branch: $branch, check_sync_enabled: true, mirror_in_enabled: true}')

filesync_global_lock_acquire
trap 'filesync_global_lock_release' EXIT
jq --argjson entry "$NEW_ENTRY" '. + [$entry]' "$repos" >"${repos}.tmp"
mv "${repos}.tmp" "$repos"
filesync_global_lock_release
trap - EXIT

echo "" >&2
echo -e "${GREEN}Added global repo:${NC} name=$name url=$url path=$path branch=$branch" >&2
