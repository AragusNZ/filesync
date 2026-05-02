#!/usr/bin/env bash
# Resolve a path to the canonical master key and enumerate sibling mappings across union project roots.
# Requires: filesync_command_init; source after lib/colors.sh (for stderr messages).

_LIB_FRM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_FRM}/filesync-projects.sh"
# shellcheck source=/dev/null
source "${_LIB_FRM}/repos-json.sh"

declare -a FILESYNC_REL_PROJECT_ROOTS=()
declare -a FILESYNC_RELATED_LINES=()
declare -A FILESYNC_REL_ROOT_TO_LOCALS=()

# Globals set by filesync_file_rel_gather_from_path:
#   FILESYNC_REL_MODE FILESYNC_REL_RNAME FILESYNC_REL_RFP FILESYNC_REL_RID FILESYNC_REL_MATCH_LP FILESYNC_REL_ABS_TARGET
#   FILESYNC_REL_PROJECT_ROOTS FILESYNC_RELATED_LINES FILESYNC_REL_ROOT_TO_LOCALS
# Args: local_arg (path to an existing regular file). Returns 1 on error.
filesync_file_rel_gather_from_path() {
  local local_arg="${1:?}"
  local match_lp="" abs_target found="" rname rpath repo_dir rel proot fj lp line

  FILESYNC_RELATED_LINES=()
  FILESYNC_REL_ROOT_TO_LOCALS=()
  FILESYNC_REL_PROJECT_ROOTS=()

  if [[ ! -e "$local_arg" ]]; then
    echo -e "${RED}Not found: $local_arg${NC}" >&2
    return 1
  fi
  if [[ ! -f "$local_arg" ]]; then
    echo -e "${RED}Not a regular file: $local_arg${NC}" >&2
    return 1
  fi
  abs_target="$(filesync_canonical_existing "$local_arg")" || return 1
  # shellcheck disable=SC2034  # read by callers after return (e.g. info-file.sh)
  FILESYNC_REL_ABS_TARGET="$abs_target"

  match_lp=""
  while IFS= read -r lp || [[ -n "${lp:-}" ]]; do
    [[ -z "$lp" || "$lp" == "null" ]] && continue
    # shellcheck disable=SC2153
    full_lp="$PROJECT_ROOT/$lp"
    [[ -f "$full_lp" ]] || continue
    if [[ "$(filesync_canonical_existing "$full_lp")" == "$abs_target" ]]; then
      match_lp="$lp"
      break
    fi
  done < <(jq -r '.[] | .local_path // empty' "$FILESYNC_FILES_FILE")

  # shellcheck disable=SC2034  # read by callers after return (e.g. info-file.sh)
  FILESYNC_REL_MATCH_LP="$match_lp"
  FILESYNC_REL_MODE=""
  FILESYNC_REL_RID=""
  FILESYNC_REL_RNAME=""
  FILESYNC_REL_RFP=""

  if [[ -n "$match_lp" ]]; then
    # shellcheck disable=SC2034  # read by callers after return (e.g. info-file.sh)
    FILESYNC_REL_MODE="clone"
    FILESYNC_REL_RID=$(jq -r --arg lp "$match_lp" '.[] | select(.local_path == $lp) | .repo_id // ""' "$FILESYNC_FILES_FILE" | head -1)
    if [[ -z "$FILESYNC_REL_RID" || "$FILESYNC_REL_RID" == "null" ]]; then
      echo -e "${RED}files.json row for $match_lp has no repo_id (set repo_id in files.json or remove the row).${NC}" >&2
      return 1
    fi
    FILESYNC_REL_RNAME="$(filesync_repo_name_from_id "$FILESYNC_REPOS_FILE" "$FILESYNC_REL_RID")"
    if [[ -z "$FILESYNC_REL_RNAME" ]]; then
      echo -e "${RED}Unknown repo_id '$FILESYNC_REL_RID' in files.json row for $match_lp.${NC}" >&2
      return 1
    fi
    FILESYNC_REL_RFP=$(jq -r --arg lp "$match_lp" '.[] | select(.local_path == $lp) | .repo_file_path // ""' "$FILESYNC_FILES_FILE" | head -1)
  else
    # shellcheck disable=SC2034  # read by callers after return (e.g. info-file.sh)
    FILESYNC_REL_MODE="master-at-checkout"
    found=""
    while IFS= read -r rname && IFS= read -r rpath; do
      [[ -z "$rpath" || "$rpath" == "null" ]] && continue
      repo_dir="$(filesync_resolve_repo_checkout_dir "$REPO_PATH_ROOT" "$rpath")"
      [[ -z "$repo_dir" ]] && continue
      repo_dir="$(cd "$repo_dir" && pwd -P)"
      case "$abs_target" in
        "$repo_dir" | "$repo_dir"/*) ;;
        *) continue ;;
      esac
      rel="${abs_target#"$repo_dir"/}"
      if [[ -f "$abs_target" ]]; then
        FILESYNC_REL_RNAME="$rname"
        FILESYNC_REL_RFP="$rel"
        found=1
        break
      fi
    done < <(jq -r '.[] | (.name // ""), (.path // "")' "$FILESYNC_REPOS_FILE")
    if [[ -z "${found:-}" ]]; then
      echo -e "${RED}Path is not a tracked clone in this project and not under any resolvable repo checkout.${NC}" >&2
      return 1
    fi
    FILESYNC_REL_RID="$(filesync_global_repos_id_for_name "$FILESYNC_REPOS_FILE" "$FILESYNC_REL_RNAME")"
  fi

  if [[ -z "${FILESYNC_REL_RFP}" || "${FILESYNC_REL_RFP}" == "null" ]]; then
    echo -e "${RED}Could not determine repo_file_path for this file.${NC}" >&2
    return 1
  fi

  mapfile -t FILESYNC_REL_PROJECT_ROOTS < <(filesync_list_union_project_roots_for_global_ops \
    "$PROJECT_ROOT" "$FILESYNC_SYSTEM_HOME" "$REPO_PATH_ROOT" "$FILESYNC_REPOS_FILE")

  for proot in "${FILESYNC_REL_PROJECT_ROOTS[@]}"; do
    [[ -z "$proot" ]] && continue
    fj="$proot/.filesync/$FILESYNC_FILES_NAME"
    [[ -f "$fj" ]] || continue
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
      [[ -z "$line" ]] && continue
      FILESYNC_RELATED_LINES+=("$proot	$line")
      lp="$(printf '%s' "$line" | jq -r '.local_path // ""')"
      if [[ -n "$lp" ]]; then
        if [[ -n "${FILESYNC_REL_ROOT_TO_LOCALS[$proot]:-}" ]]; then
          FILESYNC_REL_ROOT_TO_LOCALS[$proot]="${FILESYNC_REL_ROOT_TO_LOCALS[$proot]}"$'\n'"$lp"
        else
          FILESYNC_REL_ROOT_TO_LOCALS[$proot]="$lp"
        fi
      fi
    done < <(jq -c --arg rid "$FILESYNC_REL_RID" --arg rfp "$FILESYNC_REL_RFP" '
    .[]
    | select(.repo_file_path == $rfp)
    | select(($rid != "") and ($rid != "null") and (.repo_id == $rid))
  ' "$fj" 2>/dev/null) || true
  done
}

# Refill FILESYNC_RELATED_LINES from disk (same filter). Requires prior successful gather (RID/RNAME/RFP + PROJECT_ROOTS).
filesync_file_rel_reload_related_lines() {
  FILESYNC_RELATED_LINES=()
  local proot fj line
  for proot in "${FILESYNC_REL_PROJECT_ROOTS[@]}"; do
    [[ -z "$proot" ]] && continue
    fj="$proot/.filesync/$FILESYNC_FILES_NAME"
    [[ -f "$fj" ]] || continue
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
      [[ -z "$line" ]] && continue
      FILESYNC_RELATED_LINES+=("$proot	$line")
    done < <(jq -c --arg rid "$FILESYNC_REL_RID" --arg rfp "$FILESYNC_REL_RFP" '
    .[]
    | select(.repo_file_path == $rfp)
    | select(($rid != "") and ($rid != "null") and (.repo_id == $rid))
  ' "$fj" 2>/dev/null) || true
  done
}
