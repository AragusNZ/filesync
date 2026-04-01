#!/usr/bin/env bash
# Print CLI usage summary. Dispatched as: filesync | filesync help | -h | --help
set -euo pipefail

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$_ROOT/lib/colors.sh"

_w=22
# $1 command, $2 description (line 1), $3 optional args / signature (line 2, gray)
_hcd() {
  local cmd="$1" desc="$2" args="${3-}"
  printf '  %-*s  %s\n' "$_w" "$cmd" "$desc"
  if [[ -n "$args" ]]; then
    printf '%*s%s%s%s\n' $((2 + _w + 2)) '' "$GRAY" "$args" "$NC"
  fi
}

echo 'Usage:'
echo '   filesync [-V | --version]'
echo '   filesync [help | -h | --help]'
echo '   filesync <command> [-h | --help]'
echo '   filesync <command> [arguments]'
echo ''
echo 'Map and sync files across multiple projects and/or git checkouts (.filesync/ per project).'
echo ''
echo 'Project setup:'
_hcd 'init' 'Create .filesync/ (default: cwd); establishes project root' '[directory]'
_hcd 'enable' 'Turn file sync on in merged config' ''
_hcd 'disable' 'Turn file sync off in merged config' ''
_hcd 'path-mode' 'Show or set repo path resolution mode' '[relative|absolute]'
_hcd 'progress' 'TTY progress on long loops (default percent)' '[hidden|bar|percent]'
echo ''
echo 'Inspect and sync:'
_hcd 'check (c)' 'Verify mappings; refresh row status' '[--repo=] [--file=] [--status=]'
_hcd 'sync (s)' 'Copy from masters into the project; update files.json' '[--repo=] [--file=] [--check] [--dry-run] [--force] [--showall] [--status=] [--include-detached|…]'
_hcd 'list-repos (lr)' 'List configured repos' '[--repo=]'
_hcd 'list-files (lf)' 'List mappings' '[--repo=] [--file=] [--status=] [--include-detached]'
echo ''
echo 'Mappings and repos:'
_hcd 'add-file (af)' 'Track from repo checkout; path_in_repo is under the repo; omit :local if same path' '<repo> <path_in_repo>[:<local_path>] … [--mark-master] [--also=…]'
_hcd 'add-master (am)' 'Promote local file to master; omit :path_in_repo if it matches local_path' '<repo> <local_path>[:<path_in_repo>] … [--also=…]'
_hcd 'add-clone (ac)' 'Clone from kind=master in this project into sibling(s); fails if target exists' '<target_repo> <master_path>[:<local_path>] … [--also=…]'
_hcd 'push' 'Push local content to linked master paths' '[--all] [<local_path> …]'
_hcd 'detach-file (ddf)' 'Set detached status and kind=detached marker' '<local_path> …'
_hcd 'attach-file (daf)' 'Re-couple detached rows; check each' '<local_path> …'
_hcd 'detach-repo (ddr)' 'Detach every mapping for that repo' '<repo_name>'
_hcd 'attach-repo (dar)' 'Attach every mapping for that repo' '<repo_name>'
_hcd 'remove-file (rmf)' 'Drop row; strip clone/detached marker; keep master' '[--all-missing] [<local_path> …]'
_hcd 'remove-repo (rmr)' 'Drop repo (prompts if file mappings remain; -y/--yes skips prompt)' '<repo_name> [-y|--yes]'
_hcd 'add-repo (ar)' 'Interactively add a repo' ''
_hcd 'edit-repo (er)' 'Rename updates repo_name in all files.json rows and marker lines' '<name> [--rename=] [--path=] [--url=] [--branch=]'
echo ''
echo 'Self-update:'
_hcd 'update' 'Check GitHub for newer release; prompt to install if available (git or .deb)' '[-y|--yes]'
echo ''
echo 'Help:'
_hcd 'help' 'Print this usage summary.' 'Top-level: filesync -h | filesync --help | filesync help'
echo ''
echo 'Status filters (sync, check, list-files; --status= comma-separated, OR):'
echo '   Special tokens: unset (empty field), all (non-detached unless --include-detached), error (any error_*), detached.'
echo '   Default sync (no --status=): unset, sync_required, error_missing_local; detached skipped unless --include-detached.'
echo '   With --force: also local_newer and conflict. Other tokens: synced, conflict, detached, error_* (see man page).'
echo ''
echo 'Config:'
echo '   Discovered like git: walk up from cwd for .filesync/ (config.json, repos.json, files.json).'
echo '   See docs/configuration.md'
