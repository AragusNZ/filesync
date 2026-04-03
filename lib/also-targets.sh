#!/usr/bin/env bash
# Post-process --also repo name list: drop self, enforce mirror_in_enabled.

_LIB_AT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_AT}/project-context.sh"
# shellcheck source=/dev/null
source "${_LIB_AT}/repo-flags.sh"

# Args: nameref array of repo names, project_root_canon, repo_path_root, global_repos_json
# Mutates array in place. Returns 1 if mirror_in blocks a target.
filesync_also_targets_finalize() {
  local -n _also_arr="${1:?}"
  local project_root="$2"
  local rroot="$3"
  local repos_json="$4"

  local pr_canon root root_canon filtered=()
  pr_canon="$(cd "$project_root" && pwd -P)"

  local r
  for r in "${_also_arr[@]}"; do
    root="$(filesync_resolve_also_project_root "$rroot" "$repos_json" "$r")"
    if [[ -z "$root" ]]; then
      echo "filesync: could not resolve checkout for --also repo '$r'" >&2
      return 1
    fi
    root_canon="$(cd "$root" && pwd -P)"
    if [[ "$root_canon" == "$pr_canon" ]]; then
      continue
    fi
    if ! filesync_repo_mirror_in_enabled "$repos_json" "$r"; then
      echo "filesync: repo '$r' has mirror_in_enabled false (refusing --also target)" >&2
      return 1
    fi
    filtered+=("$r")
  done
  _also_arr=("${filtered[@]}")
}
