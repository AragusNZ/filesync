#!/usr/bin/env bash
# Git branch + merge batching for filesync sync (merge_using_git). Uses globals below.

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/repo-flags.sh"

FILESYNC_SYNC_GIT_SEEN_REPO=""
FILESYNC_SYNC_GIT_ACTIVE_REPO=""
FILESYNC_SYNC_GIT_BRANCH=""
FILESYNC_SYNC_GIT_ORIG=""
declare -a FILESYNC_SYNC_GIT_PENDING_LP=()
declare -a FILESYNC_SYNC_GIT_PENDING_FM=()
declare -a FILESYNC_SYNC_GIT_PENDING_RID=()
declare -a FILESYNC_SYNC_GIT_DEFER_META_LP=()
declare -a FILESYNC_SYNC_GIT_DEFER_META_FM=()

filesync_sync_git_reset_state() {
  FILESYNC_SYNC_GIT_SEEN_REPO=""
  FILESYNC_SYNC_GIT_ACTIVE_REPO=""
  FILESYNC_SYNC_GIT_BRANCH=""
  FILESYNC_SYNC_GIT_ORIG=""
  FILESYNC_SYNC_GIT_PENDING_LP=()
  FILESYNC_SYNC_GIT_PENDING_FM=()
  FILESYNC_SYNC_GIT_PENDING_RID=()
  FILESYNC_SYNC_GIT_DEFER_META_LP=()
  FILESYNC_SYNC_GIT_DEFER_META_FM=()
}

filesync_sync_git_abort_open_batch() {
  local proot="${1:?}"
  [[ -n "${FILESYNC_SYNC_GIT_BRANCH:-}" ]] || return 0
  git -C "$proot" merge --abort 2>/dev/null || true
  if [[ -n "${FILESYNC_SYNC_GIT_ORIG:-}" ]]; then
    git -C "$proot" checkout --force "$FILESYNC_SYNC_GIT_ORIG" 2>/dev/null || true
  fi
  git -C "$proot" branch -D "${FILESYNC_SYNC_GIT_BRANCH}" 2>/dev/null || true
  FILESYNC_SYNC_GIT_BRANCH=""
  FILESYNC_SYNC_GIT_ORIG=""
  FILESYNC_SYNC_GIT_ACTIVE_REPO=""
  FILESYNC_SYNC_GIT_PENDING_LP=()
  FILESYNC_SYNC_GIT_PENDING_FM=()
  FILESYNC_SYNC_GIT_PENDING_RID=()
}

filesync_sync_git_emergency_cleanup() {
  local proot="${1:-}"
  [[ -n "$proot" ]] || return 0
  filesync_sync_git_abort_open_batch "$proot"
}

# Args: config_file repo_name — true if merge_using_git and consumer should use git batch path.
filesync_sync_git_use_merge_path() {
  local cfg="${1:?}" rn="${2:?}"
  filesync_assembled_repo_merge_using_git "$cfg" "$rn" && git -C "${PROJECT_ROOT:?}" rev-parse --is-inside-work-tree &>/dev/null
}

# When moving to a new repo row, finalize the previous repo's batch or flush deferred metadata.
# Args: project_root files_json config_file new_repo_name
filesync_sync_git_repo_transition() {
  local proot="${1:?}"
  local files_json="${2:?}"
  local cfg="${3:?}"
  local new_repo="${4:?}"

  if [[ "$new_repo" == "$FILESYNC_SYNC_GIT_SEEN_REPO" ]]; then
    return 0
  fi
  if [[ -n "$FILESYNC_SYNC_GIT_SEEN_REPO" ]]; then
    if ! filesync_sync_git_end_repo_work "$proot" "$files_json" "$cfg" "$FILESYNC_SYNC_GIT_SEEN_REPO"; then
      return 1
    fi
  fi
  FILESYNC_SYNC_GIT_SEEN_REPO="$new_repo"
  return 0
}

# Args: project_root files_json config_file repo_being_closed
filesync_sync_git_finish_last_repo() {
  local proot="${1:?}"
  local files_json="${2:?}"
  local cfg="${3:?}"
  [[ -n "$FILESYNC_SYNC_GIT_SEEN_REPO" ]] || return 0
  filesync_sync_git_end_repo_work "$proot" "$files_json" "$cfg" "$FILESYNC_SYNC_GIT_SEEN_REPO"
  return $?
}

filesync_sync_git_end_repo_work() {
  local proot="$1" files_json="$2" cfg="$3" lr="$4"
  if [[ -n "${FILESYNC_SYNC_GIT_ACTIVE_REPO}" ]] && [[ "$FILESYNC_SYNC_GIT_ACTIVE_REPO" == "$lr" ]] && [[ -n "${FILESYNC_SYNC_GIT_BRANCH}" ]]; then
    filesync_sync_git_finalize_merge_batch "$proot" "$files_json" "$cfg" "$lr"
    return $?
  fi
  filesync_sync_git_flush_deferred_meta "$proot" "$files_json"
  return 0
}

filesync_sync_git_flush_deferred_meta() {
  local proot="${1:?}"
  local files_json="${2:?}"
  local i
  for i in "${!FILESYNC_SYNC_GIT_DEFER_META_LP[@]}"; do
    filesync_write_file_row "$files_json" "$proot" "${FILESYNC_SYNC_GIT_DEFER_META_LP[$i]}" "${FILESYNC_SYNC_GIT_DEFER_META_FM[$i]}" "synced"
  done
  FILESYNC_SYNC_GIT_DEFER_META_LP=()
  FILESYNC_SYNC_GIT_DEFER_META_FM=()
}

# Args: local_path full_master
filesync_sync_git_defer_already_synced() {
  FILESYNC_SYNC_GIT_DEFER_META_LP+=("$1")
  FILESYNC_SYNC_GIT_DEFER_META_FM+=("$2")
}

# Args: local_path full_master repo_id_for_marker
filesync_sync_git_record_pending() {
  FILESYNC_SYNC_GIT_PENDING_LP+=("$1")
  FILESYNC_SYNC_GIT_PENDING_FM+=("$2")
  FILESYNC_SYNC_GIT_PENDING_RID+=("$3")
}

# Echo path of FILESYNC_FILES_FILE relative to proot (pwd -P), or return 1 if not under proot.
filesync_sync_git_repo_rel_files_json() {
  local proot="${1:?}"
  local fj="${FILESYNC_FILES_FILE:?}"
  local pa pb rel
  pa="$(cd "$proot" && pwd -P)" || return 1
  pb="$(cd "$(dirname "$fj")" && pwd -P)/$(basename "$fj")"
  if command -v realpath >/dev/null 2>&1; then
    rel="$(realpath --relative-to="$pa" "$pb" 2>/dev/null)" || return 1
  else
    [[ "$pb" == "$pa"/* ]] || return 1
    rel="${pb#"${pa}/"}"
  fi
  [[ -n "$rel" && "$rel" != ../* ]] || return 1
  printf '%s\n' "$rel"
}

# True if proot has no porcelain changes, or embedded check ran and only files.json differs from HEAD / is untracked.
filesync_sync_git_worktree_ok_for_merge_batch() {
  local proot="${1:?}"
  [[ -z "$(git -C "$proot" status --porcelain)" ]] && return 0
  [[ "${FILESYNC_SYNC_EMBEDDED_CHECK:-}" == 1 ]] || return 1
  local allowed p
  allowed="$(filesync_sync_git_repo_rel_files_json "$proot")" || return 1
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    [[ "$p" == "$allowed" ]] || return 1
  done < <(
    git -C "$proot" diff --name-only HEAD
    git -C "$proot" diff --cached --name-only HEAD
    git -C "$proot" ls-files --others --exclude-standard
  )
  return 0
}

# Start a git batch for repo (checkout new branch). Exits process if working tree not clean.
filesync_sync_git_start_batch() {
  local proot="${1:?}"
  local repo_name="${2:?}"

  if [[ "$FILESYNC_SYNC_GIT_ACTIVE_REPO" == "$repo_name" ]] && [[ -n "$FILESYNC_SYNC_GIT_BRANCH" ]]; then
    return 0
  fi
  if [[ -n "$FILESYNC_SYNC_GIT_ACTIVE_REPO" ]]; then
    echo "filesync: internal error: git batch repo mismatch" >&2
    return 1
  fi
  if ! filesync_sync_git_worktree_ok_for_merge_batch "$proot"; then
    echo "filesync: sync with merge_using_git requires a clean git working tree at ${proot}" >&2
    exit 1
  fi
  FILESYNC_SYNC_GIT_ORIG="$(git -C "$proot" symbolic-ref -q --short HEAD 2>/dev/null || git -C "$proot" rev-parse HEAD)"
  FILESYNC_SYNC_GIT_BRANCH="filesync/sync-$$-${RANDOM}"
  git -C "$proot" checkout -b "$FILESYNC_SYNC_GIT_BRANCH"
  FILESYNC_SYNC_GIT_ACTIVE_REPO="$repo_name"
}

# Args: project_root files_json config_file repo_name
# Return 1 on merge failure (caller increments FAILED).
filesync_sync_git_finalize_merge_batch() {
  local proot="${1:?}"
  local files_json="${2:?}"
  local cfg="${3:?}"
  local repo_name="${4:?}"
  local attempt br orig lp fm rid rp fp st rel conflict_line
  declare -a work_lp work_fm work_rid
  declare -a conflict_paths

  if [[ ${#FILESYNC_SYNC_GIT_PENDING_LP[@]} -eq 0 ]]; then
    git -C "$proot" checkout --force "$FILESYNC_SYNC_GIT_ORIG" 2>/dev/null || true
    git -C "$proot" branch -D "$FILESYNC_SYNC_GIT_BRANCH" 2>/dev/null || true
    FILESYNC_SYNC_GIT_BRANCH=""
    FILESYNC_SYNC_GIT_ORIG=""
    FILESYNC_SYNC_GIT_ACTIVE_REPO=""
    filesync_sync_git_flush_deferred_meta "$proot" "$files_json"
    return 0
  fi

  work_lp=("${FILESYNC_SYNC_GIT_PENDING_LP[@]}")
  work_fm=("${FILESYNC_SYNC_GIT_PENDING_FM[@]}")
  work_rid=("${FILESYNC_SYNC_GIT_PENDING_RID[@]}")
  orig="$FILESYNC_SYNC_GIT_ORIG"

  for attempt in 1 2 3; do
    br="$FILESYNC_SYNC_GIT_BRANCH"

    if [[ "$attempt" -gt 1 ]]; then
      git -C "$proot" checkout --force "$orig"
      git -C "$proot" branch -D "$br" 2>/dev/null || true
      FILESYNC_SYNC_GIT_BRANCH="filesync/sync-$$-${RANDOM}-a${attempt}"
      br="$FILESYNC_SYNC_GIT_BRANCH"
      git -C "$proot" checkout -b "$br"
      for idx in "${!work_lp[@]}"; do
        lp="${work_lp[idx]}"
        fm="${work_fm[idx]}"
        rid="${work_rid[idx]}"
        fp="$proot/$lp"
        mkdir -p "$(dirname "$fp")"
        rp=$(jq -r --arg n "$repo_name" --arg p "$lp" '
          first(.files[]? | select(.repo_name == $n and .local_path == $p) | .repo_file_path) // empty
        ' "$cfg")
        if [[ -z "$rp" || "$rp" == "null" ]]; then
          echo "filesync: could not resolve repo_file_path for ${lp}" >&2
          filesync_sync_git_abort_open_batch "$proot"
          return 1
        fi
        _rid_render="${rid}"
        if [[ -f "$fp" ]] && ! grep -q 'repo_id=' "$fp" 2>/dev/null; then
          _rid_render=""
        fi
        if ! render_clone_from_master_file "$fm" "$rp" "$repo_name" "$fp" "$_rid_render"; then
          filesync_sync_git_abort_open_batch "$proot"
          return 1
        fi
      done
    fi

    for lp in "${work_lp[@]}"; do
      git -C "$proot" add -- "$proot/$lp"
    done

    if ! git -C "$proot" commit -q -m "filesync: sync from ${repo_name} (attempt ${attempt})"; then
      echo "filesync: git commit failed during sync merge batch" >&2
      filesync_sync_git_abort_open_batch "$proot"
      return 1
    fi

    git -C "$proot" checkout --force "$orig"
    st=0
    git -C "$proot" merge --no-edit "$br" || st=$?
    if [[ "$st" -eq 0 ]]; then
      git -C "$proot" branch -d "$br"
      for idx in "${!work_lp[@]}"; do
        filesync_write_file_row "$files_json" "$proot" "${work_lp[idx]}" "${work_fm[idx]}" "synced"
      done
      FILESYNC_SYNC_GIT_BRANCH=""
      FILESYNC_SYNC_GIT_ORIG=""
      FILESYNC_SYNC_GIT_ACTIVE_REPO=""
      FILESYNC_SYNC_GIT_PENDING_LP=()
      FILESYNC_SYNC_GIT_PENDING_FM=()
      FILESYNC_SYNC_GIT_PENDING_RID=()
      filesync_sync_git_flush_deferred_meta "$proot" "$files_json"
      return 0
    fi

    conflict_paths=()
    conflict_line=""
    conflict_line="$(git -C "$proot" diff --name-only --diff-filter=U 2>/dev/null || true)"
    git -C "$proot" merge --abort 2>/dev/null || true
    while IFS= read -r rel; do
      [[ -n "$rel" ]] && conflict_paths+=("$rel")
    done <<<"$conflict_line"

    for rel in "${conflict_paths[@]}"; do
      filesync_set_file_row_sync_status "$files_json" "$rel" "conflict"
    done

    git -C "$proot" checkout --force "$orig"
    git -C "$proot" branch -D "$br" 2>/dev/null || true

    declare -a next_lp next_fm next_rid
    next_lp=()
    next_fm=()
    next_rid=()
    for idx in "${!work_lp[@]}"; do
      lp="${work_lp[idx]}"
      conflicted=false
      for rel in "${conflict_paths[@]}"; do
        if [[ "$lp" == "$rel" ]]; then
          conflicted=true
          break
        fi
      done
      if [[ "$conflicted" == false ]]; then
        next_lp+=("$lp")
        next_fm+=("${work_fm[idx]}")
        next_rid+=("${work_rid[idx]}")
      fi
    done
    work_lp=("${next_lp[@]}")
    work_fm=("${next_fm[@]}")
    work_rid=("${next_rid[@]}")

    if [[ ${#work_lp[@]} -eq 0 ]]; then
      FILESYNC_SYNC_GIT_BRANCH=""
      FILESYNC_SYNC_GIT_ORIG=""
      FILESYNC_SYNC_GIT_ACTIVE_REPO=""
      FILESYNC_SYNC_GIT_PENDING_LP=()
      FILESYNC_SYNC_GIT_PENDING_FM=()
      FILESYNC_SYNC_GIT_PENDING_RID=()
      filesync_sync_git_flush_deferred_meta "$proot" "$files_json"
      return 1
    fi

    FILESYNC_SYNC_GIT_BRANCH="filesync/sync-$$-${RANDOM}-n${attempt}"
  done

  git -C "$proot" checkout --force "$orig" 2>/dev/null || true
  FILESYNC_SYNC_GIT_BRANCH=""
  FILESYNC_SYNC_GIT_ORIG=""
  FILESYNC_SYNC_GIT_ACTIVE_REPO=""
  FILESYNC_SYNC_GIT_PENDING_LP=()
  FILESYNC_SYNC_GIT_PENDING_FM=()
  FILESYNC_SYNC_GIT_PENDING_RID=()
  filesync_sync_git_flush_deferred_meta "$proot" "$files_json"
  return 1
}
