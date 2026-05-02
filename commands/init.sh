#!/usr/bin/env bash
# Create .filesync/files.json at the project root (cwd or path) and ensure system-level store.
# Usage: filesync init [directory] [--no-repo]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILESYNC_PKG_ROOT="$(cd "${_CMD_ROOT}/.." && pwd)"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync init [directory] [--no-repo]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}

Prepare a directory as a filesync project: create .filesync/ (default: current directory) and ensure
the shared data directory exists (usually ~/.filesync-root; FILESYNC_HOME overrides for automation).

Arguments:

  [directory]    Project root; defaults to cwd. Parent directories are not searched—only this folder
                 becomes the project.

Options:

  --no-repo    Skip the interactive first-repo wizard (CI / scripts).

First repo wizard:
  With a TTY and without --no-repo, init can register the first repo (name, checkout path, URL,
  branch). Inside a git checkout you get sensible defaults; you are prompted for the checkout path
  (relative to the repo path root or absolute, Enter for the default from cwd/git). Without a TTY the
  wizard is skipped automatically—add a repo later with filesync new repo, run init from a terminal,
  or use --no-repo.

Note:
  If .filesync/files.json already exists, init exits with an error.
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
source "${FILESYNC_PKG_ROOT}/lib/git-repo-hints.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/global-repo-interactive.sh"

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
      filesync_unknown_option_stderr "$1" "$FILESYNC_CMD_USAGE"
      exit 1
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        echo -e "${RED}Too many arguments${NC}" >&2
        filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
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
path_default="$(filesync_path_for_repos_json "$rroot" "$def_checkout")"
if [[ -z "$path_default" ]]; then
  echo -e "${RED}filesync: could not derive default checkout path (home=${rroot}, checkout=${def_checkout})${NC}" >&2
  exit 1
fi
def_url="${FILESYNC_GIT_HINT_URL:-}"
def_branch="${FILESYNC_GIT_HINT_BRANCH:-main}"

echo "" >&2
echo -e "${BOLD}${WHITE}Register this project in global ${FILESYNC_GLOBAL_REPOS_NAME}${NC}" >&2
if [[ -n "$FILESYNC_GIT_HINT_TOP" ]]; then
  echo -e "${GRAY}(defaults from git work tree: ${FILESYNC_GIT_HINT_TOP})${NC}" >&2
fi
filesync_global_repo_print_path_banner "$rroot" "$def_checkout" "$path_default"

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

path="$(filesync_global_repo_prompt_stored_path "$rroot" "$def_checkout" "$path_default")" || {
  echo -e "${RED}filesync: checkout path must be an existing directory (relative to repo path root or absolute).${NC}" >&2
  exit 1
}

if [[ -n "$def_url" ]]; then
  read -rp "Remote URL [${def_url}]: " url
  url="${url:-$def_url}"
else
  read -rp "Remote URL (e.g. https://github.com/org/repo): " url
fi

read -rp "Branch [${def_branch}]: " branch
branch="${branch:-$def_branch}"

NEW_ENTRY="$(filesync_global_repo_row_json "$name" "$url" "$path" "$branch" "$rroot")" || {
  echo -e "${RED}filesync: could not resolve checkout directory for path=${path}${NC}" >&2
  exit 1
}

filesync_global_repo_append_row_locked "$repos" "$NEW_ENTRY"

echo "" >&2
echo -e "${GREEN}Added global repo:${NC} name=$name url=$url path=$path branch=$branch" >&2
