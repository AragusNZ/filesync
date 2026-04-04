#!/usr/bin/env bash
# Discover project roots (directories with .filesync/files.json) from the global store.

_LIB_FP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_FP}/data-names.sh"
# shellcheck source=/dev/null
source "${_LIB_FP}/paths.sh"

# Args: project_root system_home repo_path_root repos_json_path
# Union of project_root (normalized) and registered checkouts that have .filesync/files.json (sorted -u).
filesync_list_union_project_roots_for_global_ops() {
  local project_root="${1:?}"
  local system_home="${2:?}"
  local rroot="${3:?}"
  local repos_json="${4:?}"
  project_root="$(cd "$project_root" && pwd -P)"
  { printf '%s\n' "$project_root"; filesync_list_project_roots_from_global_store "$system_home" "$rroot" "$repos_json"; } | sort -u
}

# Args: checkout_abs repo_path_root repos_json_path
# Print first global repo .name whose resolved checkout equals checkout_abs (pwd -P). Empty line if none.
filesync_repo_name_for_checkout_dir() {
  local checkout_abs="$1" rroot="$2" repos_json="$3"
  [[ -f "$repos_json" ]] || return 1
  checkout_abs="$(cd "$checkout_abs" && pwd -P)"
  local name path abs_repo
  while IFS= read -r name && IFS= read -r path; do
    [[ -z "${path:-}" || "$path" == "null" ]] && continue
    abs_repo="$(filesync_resolve_repo_checkout_dir "$rroot" "$path")"
    [[ -z "$abs_repo" ]] && continue
    abs_repo="$(cd "$abs_repo" && pwd -P 2>/dev/null)" || continue
    [[ "$abs_repo" == "$checkout_abs" ]] && { printf '%s\n' "$name"; return 0; }
  done < <(jq -r '.[] | (.name // ""), (.path // "")' "$repos_json")
  return 1
}

# Args: files_json_path repo_id — print count of rows with .repo_id == repo_id.
filesync_count_files_json_rows_for_repo() {
  local fp="$1" rid="$2"
  [[ -f "$fp" ]] || {
    printf '0\n'
    return 0
  }
  jq --arg id "$rid" '[.[] | select(.repo_id == $id)] | length' "$fp"
}

# Args: system_home repo_path_root repos_json_path
# Print unique absolute project roots, one per line (sorted -u).
filesync_list_project_roots_from_global_store() {
  local system_home="${1:?}"
  local rroot="${2:?}"
  local repos_json="${3:?}"
  [[ -f "$repos_json" ]] || return 0
  if ! jq -e 'type == "array"' "$repos_json" &>/dev/null; then
    return 0
  fi
  local -a roots=()
  local path abs fjson
  while IFS= read -r path || [[ -n "${path:-}" ]]; do
    [[ -z "$path" || "$path" == "null" ]] && continue
    abs="$(filesync_resolve_repo_checkout_dir "$rroot" "$path")"
    [[ -z "$abs" ]] && continue
    fjson="$abs/.filesync/${FILESYNC_FILES_NAME}"
    if [[ -f "$fjson" ]] && jq -e 'type == "array"' "$fjson" &>/dev/null; then
      roots+=("$(cd "$abs" && pwd -P)")
    fi
  done < <(jq -r '.[].path // empty' "$repos_json")
  if [[ ${#roots[@]} -eq 0 ]]; then
    return 0
  fi
  printf '%s\n' "${roots[@]}" | sort -u
}

# Args: cwd (absolute) system_home repo_path_root repos_json_path
# Echo one project root (absolute) if cwd is inside a registered checkout that has files.json; else empty.
filesync_project_root_from_registered_repos() {
  local cwd="${1:?}"
  local system_home="${2:?}"
  local rroot="${3:?}"
  local repos_json="${4:?}"
  cwd="$(cd "$cwd" && pwd -P)"
  local best="" best_len=0 abs fjson plen
  local path
  while IFS= read -r path || [[ -n "${path:-}" ]]; do
    [[ -z "$path" || "$path" == "null" ]] && continue
    abs="$(filesync_resolve_repo_checkout_dir "$rroot" "$path")"
    [[ -z "$abs" ]] && continue
    abs="$(cd "$abs" && pwd -P)"
    fjson="$abs/.filesync/${FILESYNC_FILES_NAME}"
    [[ -f "$fjson" ]] || continue
    case "$cwd" in
      "$abs" | "$abs"/*)
        plen=${#abs}
        if [[ "$plen" -gt "$best_len" ]]; then
          best="$abs"
          best_len=$plen
        fi
        ;;
    esac
  done < <(jq -r '.[].path // empty' "$repos_json")
  [[ -n "$best" ]] && printf '%s' "$best"
}

# Args: repo_id system_home repo_path_root repos_json_path
# Print "path<TAB>count" for each project files.json that has at least one row with .repo_id == repo_id.
filesync_projects_counting_repo_id() {
  local rid="${1:?}"
  local system_home="${2:?}"
  local rroot="${3:?}"
  local repos_json="${4:?}"
  local root fjson n
  while IFS= read -r root || [[ -n "${root:-}" ]]; do
    [[ -z "$root" ]] && continue
    fjson="$root/.filesync/${FILESYNC_FILES_NAME}"
    n=$(jq --arg id "$rid" '[.[] | select(.repo_id == $id)] | length' "$fjson" 2>/dev/null) || n=0
    if [[ "${n:-0}" -gt 0 ]]; then
      printf '%s\t%s\n' "$fjson" "$n"
    fi
  done < <(filesync_list_project_roots_from_global_store "$system_home" "$rroot" "$repos_json")
}

