#!/usr/bin/env bash
# CLI: filesync add clone — add clone file + mapping in a sibling project from a kind=master file in the current project.

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync add clone <target_repo_or_collection> <master_path>[:<local_path>] ... [--also=names]'
if filesync_argv_wants_help "$@"; then
  cat <<EOF
${FILESYNC_CMD_USAGE}
Also: a -c

Clone mappings from a kind=master file in this project into a sibling repo: creates the
target-side file and row. Fails if the target local file already exists.

The first argument is a repo name or a collection name (expanded like --also=). Multiple
targets are merged with --also= (deduplicated); the current project checkout is skipped.

Options:
  --also=names         Comma-separated repo names and/or collection names

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/runtime.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/files-append.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/collections.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/also-targets.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/repo-flags.sh"
filesync_command_init "${BASH_SOURCE[0]}"

trap 'rm -f "${FILESYNC_STATE_FILE:-}"' EXIT

TARGET_REPOS_RAW=""
declare -a POSITIONAL_RAW=()

for arg in "$@"; do
  if [[ "$arg" == --also=* ]]; then
    TARGET_REPOS_RAW="${arg#--also=}"
  elif [[ "$arg" == --* ]]; then
    filesync_unknown_option_stderr "$arg" "$FILESYNC_CMD_USAGE"
    exit 1
  else
    POSITIONAL_RAW+=("$arg")
  fi
done

if [[ ${#POSITIONAL_RAW[@]} -lt 2 ]]; then
  filesync_usage_error_stderr "$FILESYNC_CMD_USAGE"
  exit 1
fi

PRIMARY_TARGET_RAW="${POSITIONAL_RAW[0]}"
declare -a POSITIONAL=("${POSITIONAL_RAW[@]:1}")
declare -a MASTER_PATHS=()
declare -a TARGET_LOCAL_PATHS=()

for token in "${POSITIONAL[@]}"; do
  if [[ "$token" == *":"* ]]; then
    MASTER_PATHS+=("${token%%:*}")
    TARGET_LOCAL_PATHS+=("${token#*:}")
  else
    MASTER_PATHS+=("$token")
    TARGET_LOCAL_PATHS+=("$token")
  fi
done

declare -A SEEN_TARGET_LOCAL=()
for i in "${!TARGET_LOCAL_PATHS[@]}"; do
  lp="${TARGET_LOCAL_PATHS[$i]}"
  if [[ -n "${SEEN_TARGET_LOCAL[$lp]:-}" ]]; then
    echo -e "${RED}Error: Duplicate target local_path '$lp'.${NC}" >&2
    exit 1
  fi
  SEEN_TARGET_LOCAL["$lp"]=1
done

declare -a PRIMARY_EXPANDED=()
if ! filesync_also_expand_to_array "$PRIMARY_TARGET_RAW" "$FILESYNC_REPOS_FILE" "$FILESYNC_COLLECTIONS_FILE" PRIMARY_EXPANDED; then
  exit 1
fi

declare -a ALSO_REPOS=()
if ! filesync_also_expand_to_array "$TARGET_REPOS_RAW" "$FILESYNC_REPOS_FILE" "$FILESYNC_COLLECTIONS_FILE" ALSO_REPOS; then
  exit 1
fi

declare -a ALL_TARGET_REPOS=()
declare -A SEEN_ALL_TARGETS=()
for r in "${PRIMARY_EXPANDED[@]}"; do
  [[ -n "${SEEN_ALL_TARGETS[$r]:-}" ]] && continue
  SEEN_ALL_TARGETS[$r]=1
  ALL_TARGET_REPOS+=("$r")
done
for r in "${ALSO_REPOS[@]}"; do
  [[ -n "${SEEN_ALL_TARGETS[$r]:-}" ]] && continue
  SEEN_ALL_TARGETS[$r]=1
  ALL_TARGET_REPOS+=("$r")
done

if ! filesync_also_targets_finalize ALL_TARGET_REPOS "$PROJECT_ROOT" "$REPO_PATH_ROOT" "$FILESYNC_REPOS_FILE"; then
  exit 1
fi

if [[ ${#ALL_TARGET_REPOS[@]} -eq 0 ]]; then
  echo -e "${RED}Error: No target repos after resolving targets (only the current project matched, or all targets were skipped).${NC}" >&2
  exit 1
fi

for target_repo in "${ALL_TARGET_REPOS[@]}"; do
  if ! filesync_repo_mirror_in_enabled "$FILESYNC_REPOS_FILE" "$target_repo"; then
    echo -e "${RED}Error: Target repo '$target_repo' has mirror_in_enabled false.${NC}" >&2
    exit 1
  fi
done

# Echo inferred repo name for source project (PROJECT_ROOT) using global repos catalog, or fail.
infer_source_repo_name_at_target() {
  local source_project_root="$1"
  local repos_json="$2"
  local repo_root="$3"
  local name path resolved found="" n=0

  while IFS=$'\t' read -r name path; do
    path="${path//$'\r'/}"
    [[ -z "$path" || "$path" == "null" ]] && continue
    resolved="$(filesync_resolve_repo_checkout_dir "$repo_root" "$path")"
    [[ -z "$resolved" ]] && continue
    if [[ "$resolved" == "$source_project_root" ]]; then
      if [[ $n -eq 0 ]]; then
        found="$name"
      fi
      n=$((n + 1))
    fi
  done < <(jq -r '.[] | [.name, (.path // "")] | @tsv' "$repos_json")

  if [[ $n -eq 0 ]]; then
    echo -e "${RED}Error: No global repo entry resolves to this project root ($source_project_root).${NC}" >&2
    return 1
  fi
  if [[ $n -gt 1 ]]; then
    echo -e "${RED}Error: Multiple global repos resolve to this project root; cannot infer repo= name uniquely.${NC}" >&2
    return 1
  fi
  printf '%s\n' "$found"
}

validate_target_repo_entry() {
  local target_repo="$1"
  if ! jq -e --arg n "$target_repo" 'any(.name == $n)' "$FILESYNC_REPOS_FILE" &>/dev/null; then
    echo -e "${RED}Error: Target repo '$target_repo' is not in current repos.${NC}" >&2
    return 1
  fi
  # shellcheck disable=SC2153
  local target_project_root ofs
  target_project_root="$(filesync_resolve_also_project_root "$REPO_PATH_ROOT" "$FILESYNC_REPOS_FILE" "$target_repo")"
  if [[ -z "$target_project_root" ]]; then
    echo -e "${RED}Error: Target repo '$target_repo' has no resolvable checkout path.${NC}" >&2
    return 1
  fi
  ofs="$target_project_root/.filesync"
  if [[ ! -f "$ofs/$FILESYNC_FILES_NAME" ]]; then
    echo -e "${RED}Error: Target '$target_repo' is not an initialized filesync project: missing $ofs/$FILESYNC_FILES_NAME.${NC}" >&2
    return 1
  fi
  printf '%s\n' "$target_project_root"
}

declare -A TARGET_ROOT_BY_REPO=()
declare -A INFERRED_REPO_NAME_BY_TARGET=()

for target_repo in "${ALL_TARGET_REPOS[@]}"; do
  root="$(validate_target_repo_entry "$target_repo")" || exit 1
  TARGET_ROOT_BY_REPO["$target_repo"]="$root"
  ir="$(infer_source_repo_name_at_target "$PROJECT_ROOT" "$FILESYNC_REPOS_FILE" "$REPO_PATH_ROOT")" || exit 1
  INFERRED_REPO_NAME_BY_TARGET["$target_repo"]="$ir"
done

# Validate sources (paths relative to current project); do not modify yet.
for i in "${!MASTER_PATHS[@]}"; do
  mp="${MASTER_PATHS[$i]}"
  full_master="$PROJECT_ROOT/$mp"
  if [[ ! -f "$full_master" ]]; then
    echo -e "${RED}Error: Master file not found: $mp${NC}" >&2
    exit 1
  fi
  if has_master_file_sync_marker "$full_master"; then
    :
  elif has_any_file_sync_marker "$full_master"; then
    echo -e "${RED}Error: Source file has a filesync marker that is not kind=master: $mp${NC}" >&2
    exit 1
  fi
done

# Precheck: no existing clone file or files.json row in any target (before prepending markers).
for target_repo in "${ALL_TARGET_REPOS[@]}"; do
  troot="${TARGET_ROOT_BY_REPO[$target_repo]}"
  ofs="$troot/.filesync"
  files_path="$ofs/$FILESYNC_FILES_NAME"
  for i in "${!MASTER_PATHS[@]}"; do
    tlp="${TARGET_LOCAL_PATHS[$i]}"
    full_local="$troot/$tlp"
    if [[ -e "$full_local" ]]; then
      echo -e "${RED}Error: Target file already exists ($target_repo): $tlp${NC}" >&2
      exit 1
    fi
    if jq -e --arg local "$tlp" '.[] | select(.local_path == $local)' "$files_path" &>/dev/null; then
      echo -e "${RED}Error: local_path '$tlp' already exists in $target_repo .filesync/$(basename "$files_path").${NC}" >&2
      exit 1
    fi
  done
done

# Auto-prepend kind=master when no marker (after all prechecks).
for i in "${!MASTER_PATHS[@]}"; do
  mp="${MASTER_PATHS[$i]}"
  full_master="$PROJECT_ROOT/$mp"
  if ! has_any_file_sync_marker "$full_master"; then
    if ! prepend_master_marker_to_file "$full_master" "$mp"; then
      echo -e "${RED}Error: Could not prepend kind=master marker to: $mp${NC}" >&2
      exit 1
    fi
    echo -e "${GREEN}Prepended kind=master to:${NC} $mp" >&2
  fi
  if ! has_master_file_sync_marker "$full_master"; then
    echo -e "${RED}Error: Source file must have kind=master after update: $mp${NC}" >&2
    exit 1
  fi
done

add_clone_one() {
  local target_project_root="$1"
  local files_path="$2"
  local repos_path="$3"
  local inferred_repo_name="$4"
  local master_path="$5"
  local local_path="$6"
  local label="$7"

  local full_master full_local tmp_clone rmi lmi new_entry rid
  rid="$(filesync_global_repos_id_for_name "$repos_path" "$inferred_repo_name")"
  full_master="$PROJECT_ROOT/$master_path"
  full_local="$target_project_root/$local_path"
  mkdir -p "$(dirname "$full_local")"
  tmp_clone="$(mktemp)"
  if ! render_clone_from_master_file "$full_master" "$master_path" "$inferred_repo_name" "$tmp_clone" "$rid"; then
    rm -f "$tmp_clone"
    echo -e "${RED}Error: Could not render clone from master: $master_path (${label})${NC}" >&2
    return 1
  fi
  cp "$tmp_clone" "$full_local"
  rm -f "$tmp_clone"

  rmi=$(file_sync_mtime_iso "$full_master")
  lmi=$(file_sync_mtime_iso "$full_local")

  new_entry=$(jq -n \
    --arg id "$rid" \
    --arg repo_path "$master_path" \
    --arg local "$local_path" \
    --arg rmi "${rmi:-}" \
    --arg lmi "${lmi:-}" \
    '{
      repo_id: $id,
      repo_file_path: $repo_path,
      local_path: $local,
      sync_status: "sync_required",
      last_sync_at: null,
      last_check_at: null,
      repo_file_modified_at: (if $rmi == "" then null else $rmi end),
      local_file_modified_at: (if $lmi == "" then null else $lmi end)
    }')

  filesync_files_append_entry "$files_path" "$repos_path" "$inferred_repo_name" "$new_entry" || return 1
  echo -e "${GREEN}Added clone in ${label}:${NC} repo=$inferred_repo_name repo_file_path=$master_path local_path=$local_path" >&2
}

for target_repo in "${ALL_TARGET_REPOS[@]}"; do
  troot="${TARGET_ROOT_BY_REPO[$target_repo]}"
  ofs="$troot/.filesync"
  inferred="${INFERRED_REPO_NAME_BY_TARGET[$target_repo]}"
  for i in "${!MASTER_PATHS[@]}"; do
    add_clone_one "$troot" "$ofs/$FILESYNC_FILES_NAME" "$FILESYNC_REPOS_FILE" "$inferred" \
      "${MASTER_PATHS[$i]}" "${TARGET_LOCAL_PATHS[$i]}" "project at $troot ($target_repo)" \
      || filesync_die "add-clone failed (see messages above)"
  done
done
