#!/usr/bin/env bash
# Print CLI usage summary. Dispatched as: filesync | filesync help | -h | --help
set -euo pipefail

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$_ROOT/lib/colors.sh"

_w=26
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
echo 'Map and sync files across multiple projects and/or git checkouts (project .filesync/ + global store).'
echo ''
echo 'Project setup:'
_hcd 'init' 'Create .filesync/files.json; ensures system store; interactive global repo if TTY' '[directory] [--no-repo]'
_hcd 'config' 'Show/doctor/set preferences; doctor validates repos, files.json, clone/master markers; summary line' 'show | doctor | set progress <hidden|bar|percent>'
_hcd 'migrate' 'Import per-project repos/collections/config into global store (one-shot)' 'From a project with legacy .filesync/repos.json; see filesync migrate -h'
_hcd 'handle-missing' 'Repair rows when master or local paths are missing (non-interactive flags)' 'Project cwd; <local_path> + one action; see filesync handle-missing -h'
echo ''
echo 'Inspect and sync:'
_hcd 'check (c)' 'Verify mappings; refresh row status' '[--repo=name] [--file=…] [--repo-file=…] [--all-files=…] [--status=a,b,…]'
_hcd 'info | i [-f]' 'Inspect file (same master) or repo (catalog, checkout, project rows)' '[file|-f] <path> [--fix-marker] | repo|-r <name>; i <path> omits file/-f'
_hcd 'retarget' 'After git mv: retarget clone (one row) or retarget master (all sibling projects); see retarget -h' 'clone <local_clone> <new_repo_path> | master <master|old_path> <new_repo_path> [--move|--mv]  (-c / -m)'
_hcd 'sync (s)' 'Copy from masters into the project; update files.json' '[--repo=name] [--file=…] [--repo-file=…] [--all-files=…] [-c|--check] [--dry-run] [-f|--force] [--showall] [--status=a,b,…] [--include-detached] [--move|--mv]'
_hcd 'list repos (l -r)' 'List configured repos' '[--repo=]'
_hcd 'list files (l | l -f)' 'List mappings' '[--repo=] [--file=] [--repo-file=] [--all-files=] [--status=] [--include-detached]'
_hcd 'list collections (l -col)' 'List repo collections (--also=)' ''
echo ''
echo 'Mappings and repos:'
_hcd 'add file (a | a -f)' 'Track from repo checkout; path_in_repo is under the repo; omit :local if same path' '<repo> <path_in_repo>[:<local_path>] … [--mark-master] [--also=repos_or_collections]'
_hcd 'add master (a -m)' 'Promote/create master in another repo'\''s tree; paths here become clones; omit :path_in_repo if same as local' '<repo> <local_path>[:<path_in_repo>] … [--also=repos_or_collections]'
_hcd 'add clone (a -c)' 'kind=master here; clone file + row in sibling(s); fails if target path exists' '<target_repo> <master_path>[:<local_path>] … [--also=repos_or_collections]'
_hcd 'push' 'Push local to master paths, or master out to all clone rows (--to-clones)' '[--all] [<local_path> …] | --to-clones <path> [--dry-run]'
_hcd 'detach file (d | d -f)' 'Set detached status and kind=detached marker' '<local_path> …'
_hcd 'detach files-in-repo (d -fir)' 'Detach every mapping for that repo' '<repo_name>'
_hcd 'attach file (da | da -f)' 'Re-couple detached rows; check each' '<local_path> …'
_hcd 'attach files-in-repo (da -fir)' 'Attach every mapping for that repo' '<repo_name>'
_hcd 'remove file (rm | rm -f)' 'Drop row; strip clone/detached marker; keep master' '[--all-missing] [<local_path> …]'
_hcd 'remove repo (rm -r)' 'Drop repo (--force if mappings remain; then prompt unless -y/--yes)' '<repo_name> [--force] [-y|--yes]'
_hcd 'remove collection (rm -col)' 'Delete a collection' '<name>'
_hcd 'new repo (n -r)' 'Interactively add a repo' ''
_hcd 'edit repo (e -r)' 'Update global repos.json only (no project files.json or markers)' '<repo_name> [options] (see filesync edit repo -h)'
_hcd 'new collection (n -col)' 'Named repo group for --also= (optional --repos=a,b)' '<name> [--repos=a,b]'
_hcd 'edit collection (e -col)' 'Rename collection or add/remove repo members' '<name> [options] (see filesync edit collection -h)'
echo ''
echo 'Self-update:'
_hcd 'update' 'Check GitHub for newer release; prompt to install if available (git or .deb)' '[-y|--yes]'
echo ''
echo 'Help:'
_hcd 'help' 'Print this usage summary.' 'Top-level: filesync -h | filesync --help | filesync help'
echo ''
echo 'Status filters (sync, check, list files; --status= comma-separated, OR):'
echo '   Special tokens: unset (empty field), all (non-detached unless --include-detached), error (any error_*), detached.'
echo '   Default sync (no --status=): unset, sync_required, error_missing_local, master_file_moved; detached skipped unless --include-detached.'
echo '   With -f/--force: also local_newer and conflict. Other tokens: synced, conflict, detached, error_* (see man page).'
echo ''
echo '   merge_using_git (per repo in global repos.json): when true and the git work tree has no'
echo '   dirty paths except possibly .filesync/files.json, sync uses a short-lived branch and merge; see docs/configuration.md.'
echo ''
echo 'Config:'
echo '   Project: walk up from cwd for .filesync/ (files.json only after init).'
echo '   Global store: ~/.filesync-root (repos.json, collections.json, system.json, preferences.json);'
echo '   FILESYNC_HOME overrides the path for tests/automation only (see docs/configuration.md).'
echo '   list repos and list collections use the global store only; list files needs a project.'
