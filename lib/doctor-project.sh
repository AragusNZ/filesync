#!/usr/bin/env bash
# Project-scoped checks for filesync doctor inspect (sourced; no set -e at top level).
# Requires: filesync_command_init, lib/doctor-format.sh sourced by caller (colors).

_LIB_DP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DP}/file-related-mappings.sh"

filesync_doctor_project_find_print0() {
  [[ -n "${PROJECT_ROOT:-}" ]] || return 1
  find "$PROJECT_ROOT" \( -name .git -o -name node_modules \) -prune -o -type f -print0 2>/dev/null
}

# files.json: duplicate local_path and unknown repo_id (global catalog).
filesync_doctor_project_files_json_sanity() {
  local row lp rid rname dups dup_lp
  [[ -f "$FILESYNC_FILES_FILE" ]] || return 0

  filesync_doctor_subsection "files.json structure"

  dups="$(jq -r '
    group_by(.local_path // "")
    | map(select(length > 1) | .[0].local_path // "")
    | map(select(. != ""))
    | unique
    | .[]' "$FILESYNC_FILES_FILE" 2>/dev/null)" || true
  if [[ -n "${dups// }" ]]; then
    while IFS= read -r dup_lp || [[ -n "${dup_lp:-}" ]]; do
      [[ -z "${dup_lp// }" ]] && continue
      filesync_doctor_warn_msg "Warning: duplicate local_path in files.json: $dup_lp"
    done <<<"$dups"
  else
    filesync_doctor_info "No duplicate local_path entries."
  fi

  declare -A seen_unknown_rid=()
  while IFS= read -r rid || [[ -n "${rid:-}" ]]; do
    [[ -z "$rid" || "$rid" == "null" ]] && continue
    [[ -n "${seen_unknown_rid[$rid]:-}" ]] && continue
    if ! jq -e --arg id "$rid" 'any(.[]?; .id == $id)' "$FILESYNC_REPOS_FILE" &>/dev/null; then
      seen_unknown_rid[$rid]=1
      filesync_doctor_warn_msg "Warning: files.json references unknown repo_id (not in global repos.json): $rid"
    fi
  done < <(jq -r '.[].repo_id // empty' "$FILESYNC_FILES_FILE" | sort -u)
}

# For each non-detached row with a coupled clone marker, path=/repo=/repo_id= must match files.json + catalog.
filesync_doctor_project_clone_markers_vs_rows() {
  local row lp rfp rid rname full sync_st
  [[ -f "$FILESYNC_FILES_FILE" ]] || return 0

  filesync_doctor_subsection "Clone markers vs catalog"

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    sync_st="$(jq -r '.sync_status // ""' <<<"$row")"
    [[ "$sync_st" == "detached" ]] && continue
    lp="$(jq -r '.local_path // ""' <<<"$row")"
    rfp="$(jq -r '.repo_file_path // ""' <<<"$row")"
    rid="$(jq -r '.repo_id // ""' <<<"$row")"
    [[ -z "$lp" || "$lp" == "null" ]] && continue
    full="$PROJECT_ROOT/$lp"
    [[ -f "$full" ]] || continue
    has_clone_file_sync_marker "$full" 2>/dev/null || continue
    has_detached_clone_file_sync_marker "$full" 2>/dev/null && continue
    if ! filesync_marker_read_clone_tokens_from_file "$full" 2>/dev/null; then
      continue
    fi
    rname="$(filesync_repo_name_from_id "$FILESYNC_REPOS_FILE" "$rid")"
    if [[ -n "$FILESYNC_CLONE_M_PATH" && "$FILESYNC_CLONE_M_PATH" != "$rfp" ]]; then
      filesync_doctor_warn_msg "Warning: clone marker path= does not match files.json repo_file_path for $lp"
      filesync_doctor_detail "marker path=${FILESYNC_CLONE_M_PATH} row repo_file_path=${rfp}"
    fi
    if [[ -n "$rname" && -n "$FILESYNC_CLONE_M_REPO" && "$FILESYNC_CLONE_M_REPO" != "$rname" ]]; then
      filesync_doctor_warn_msg "Warning: clone marker repo= does not match catalog for $lp"
      filesync_doctor_detail "marker repo=${FILESYNC_CLONE_M_REPO} expected repo name=${rname}"
    fi
    if [[ -n "$FILESYNC_CLONE_M_REPO_ID" && "$FILESYNC_CLONE_M_REPO_ID" != "$rid" ]]; then
      filesync_doctor_warn_msg "Warning: clone marker repo_id= does not match files.json for $lp"
      filesync_doctor_detail "marker repo_id=${FILESYNC_CLONE_M_REPO_ID} row repo_id=${rid}"
    fi
  done < <(jq -c '.[]' "$FILESYNC_FILES_FILE" 2>/dev/null)
}

# Coupled clone marker on disk but no files.json row for that local_path.
filesync_doctor_project_orphan_clone_markers() {
  local f canon rel_lp marker_kind
  declare -A seen_orphan=()

  filesync_doctor_subsection "Orphan clone/detached markers"

  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    marker_kind=""
    if has_detached_file_sync_marker "$f" 2>/dev/null; then
      marker_kind="detached"
    elif has_clone_file_sync_marker "$f" 2>/dev/null; then
      if has_detached_clone_file_sync_marker "$f" 2>/dev/null; then
        marker_kind="detached"
      else
        marker_kind="clone"
      fi
    fi
    [[ -n "$marker_kind" ]] || continue
    canon="$(filesync_canonical_existing "$f" 2>/dev/null)" || continue
    case "$canon" in
      "$PROJECT_ROOT" | "$PROJECT_ROOT"/*) ;;
      *) continue ;;
    esac
    rel_lp="${canon#"$PROJECT_ROOT"/}"
    [[ -n "${seen_orphan[$rel_lp]:-}" ]] && continue
    if jq -e --arg lp "$rel_lp" 'any(.[]?; (.local_path // "") == $lp)' "$FILESYNC_FILES_FILE" &>/dev/null; then
      continue
    fi
    seen_orphan[$rel_lp]=1
    filesync_doctor_warn_msg "Warning: kind=${marker_kind} marker but no files.json row for local_path: $rel_lp"
    filesync_doctor_detail "Run filesync info file or remove the marker if the file is not tracked."
  done < <(filesync_doctor_project_find_print0)
}

filesync_doctor_project_scan_master_markers() {
  local f canon rel_hint key_master maybe
  declare -A seen_path=()
  declare -A seen_noclone_key=()

  filesync_doctor_subsection "Master markers"

  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    has_master_file_sync_marker "$f" 2>/dev/null || continue
    canon="$(filesync_canonical_existing "$f" 2>/dev/null)" || continue
    [[ -n "${seen_path[$canon]:-}" ]] && continue
    seen_path[$canon]=1

    if ! filesync_file_rel_gather_from_path "$canon" 2>/dev/null; then
      rel_hint="$canon"
      if command -v realpath >/dev/null 2>&1; then
        maybe="$(realpath --relative-to="$PROJECT_ROOT" "$canon" 2>/dev/null)" && [[ -n "$maybe" ]] && rel_hint="$maybe"
      fi
      filesync_doctor_note_msg "Note: kind=master but path is not a tracked clone nor under a registered repo checkout: $rel_hint"
      filesync_doctor_detail "Run filesync info file on this path (from the project root) to fix or strip the marker if appropriate."
      continue
    fi

    if [[ ${#FILESYNC_RELATED_LINES[@]} -eq 0 ]]; then
      key_master="${FILESYNC_REL_RID:-}|${FILESYNC_REL_RFP:-}"
      [[ -n "${seen_noclone_key[$key_master]:-}" ]] && continue
      seen_noclone_key[$key_master]=1
      filesync_doctor_warn_msg "Warning: kind=master with no tracked clones in catalog: ${FILESYNC_REL_RNAME:-?}/${FILESYNC_REL_RFP:-?}"
      filesync_doctor_detail "Master: $canon"
      filesync_doctor_detail "Run filesync info file when the marker should be removed (no copies are tracked)."
    fi
  done < <(filesync_doctor_project_find_print0)
}
