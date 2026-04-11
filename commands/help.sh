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
echo 'Keep the same file in sync across several projects or git checkouts.'
echo ''
echo 'Project setup:'
_hcd 'init' 'Start filesync in a folder (creates .filesync/); optional first repo wizard when run in a terminal' '[directory] [--no-repo]'
_hcd 'config' 'Show where data lives, run a health check, or change UI preferences' 'show | doctor | set progress <hidden|bar|percent>'
_hcd 'migrate' 'One-time upgrade: move old per-project repo lists into the shared store' 'Run inside a project that still has .filesync/repos.json; see filesync migrate -h'
_hcd 'handle-missing' 'When a synced file or its source vanished, unmap it or restore from the source copy' '<local_path> + one action flag; see filesync handle-missing -h'
echo ''
echo 'Inspect and sync:'
_hcd 'check (c)' 'Verify mappings against disk and repo checkouts; refresh row status' '[--repo=name] [--file=…] [--repo-file=…] [--all-files=…] [--status=a,b,…]'
_hcd 'info | i [-f]' 'Show how a path or repo is wired up in filesync (clones, master, catalog)' '[file|-f] <path> [--fix-marker] | repo|-r <name>; i <path> omits file/-f'
_hcd 'retarget' 'After you git mv a tracked file, update stored paths (one clone or every copy)' 'clone … | master …; see filesync retarget -h'
_hcd 'sync (s)' 'Copy from master repos into this project and refresh status' '[--repo=name] [--file=…] [--repo-file=…] [--all-files=…] [-c|--check] [--no-commit|--dirty] [--dry-run] [-f|--force] [--showall] [--status=a,b,…] [--include-detached] [--move|--mv]'
_hcd 'list repos (l -r)' 'List repos registered in the shared store' '[--repo=]'
_hcd 'list files (l | l -f)' 'List tracked files and their sync status in this project' '[--repo=] [--file=] [--repo-file=] [--all-files=] [--status=] [--include-detached]'
_hcd 'list collections (l -col)' 'List named groups of repos (for --also= when adding files)' ''
echo ''
echo 'Mappings and repos:'
_hcd 'add file (a | a -f)' 'Track a file that already lives in a repo checkout (path under that repo root)' '<repo> <path_in_repo>[:<local_path>] … [--mark-master] [--also=repos_or_collections]'
_hcd 'add master (a -m)' 'Store the source copy in another repo; this project keeps linked copies' '<repo> <local_path>[:<path_in_repo>] … [--also=repos_or_collections]'
_hcd 'add clone (a -c)' 'This project holds the source; create matching files in other projects/repos' '<target_repo> <master_path>[:<local_path>] … [--also=repos_or_collections]'
_hcd 'push' 'Copy your edits to the source file, or push the source out to all clones (--to-clones)' '[--all] [<local_path> …] | --to-clones <path> [--dry-run]'
_hcd 'detach file (d | d -f)' 'Pause syncing for these paths (keeps the mapping; marks as detached)' '<local_path> …'
_hcd 'detach files-in-repo (d -fir)' 'Detach every tracked file that uses a given repo' '<repo_name>'
_hcd 'attach file (da | da -f)' 'Re-couple detached paths: refresh from source and clear detached state' '<local_path> …'
_hcd 'attach files-in-repo (da -fir)' 'Attach every file mapped to that repo' '<repo_name>'
_hcd 'remove file (rm | rm -f)' 'Stop tracking paths (removes mapping; does not delete the source master marker)' '[--all-missing] [<local_path> …]'
_hcd 'remove repo (rm -r)' 'Remove a repo from the catalog (--force if files still reference it)' '<repo_name> [--force] [-y|--yes]'
_hcd 'remove collection (rm -col)' 'Delete a named repo group' '<name>'
_hcd 'new repo (n -r)' 'Interactively add a repo' ''
_hcd 'edit repo (e -r)' 'Change checkout path, URL, branch, or flags in the shared catalog only' '<repo_name> [options] (see filesync edit repo -h)'
_hcd 'new collection (n -col)' 'Create a named group of repos for --also= (optional starting members)' '<name> [--repos=a,b]'
_hcd 'edit collection (e -col)' 'Rename a collection or add/remove repos in it' '<name> [options] (see filesync edit collection -h)'
echo ''
echo 'Self-update:'
_hcd 'update' 'See if a newer release is on GitHub and install it (source or .deb)' '[-y|--yes]'
echo ''
echo 'Help:'
_hcd 'help' 'Print this summary.' 'filesync -h | filesync --help | filesync help'
echo ''
echo 'Status filters (sync, check, list files; --status= is comma-separated, any match):'
echo '   Shorthand: unset (empty), all (non-detached unless --include-detached), error (any error_*), detached.'
echo '   Default sync (no --status=): unset, sync_required, error_missing_local, master_file_moved; detached skipped unless --include-detached.'
echo '   With -f/--force: also local_newer and conflict. Other values: synced, conflict, detached, error_* (see man filesync).'
echo ''
echo '   merge_using_git (per repo): when enabled and the git tree is clean except possibly'
echo '   .filesync/files.json, sync may use a short branch and merge instead of writing files directly; see docs/configuration.md.'
echo ''
echo 'Where data lives:'
echo '   This project: walk up from the current directory for .filesync/ (after init).'
echo '   Shared store: ~/.filesync-root (repos, collections, preferences, etc.).'
echo '   FILESYNC_HOME overrides the store path (automation/tests only; see docs/configuration.md).'
echo '   list repos / list collections read the shared store; list files needs a project with .filesync/.'
