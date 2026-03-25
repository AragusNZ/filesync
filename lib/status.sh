#!/usr/bin/env bash
# Timestamps, sync_status, colors, row updates (sourced).

file_sync_now_epoch() {
  date -u +%s
}

file_sync_now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

file_sync_mtime_epoch() {
  local path="$1"
  if [[ -f "$path" ]]; then
    stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null
  fi
}

file_sync_epoch_to_iso() {
  local e="$1"
  date -u -d "@$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

file_sync_mtime_iso() {
  local path="$1"
  local e
  e=$(file_sync_mtime_epoch "$path")
  if [[ -n "${e:-}" ]]; then
    file_sync_epoch_to_iso "$e"
  fi
}

file_sync_parse_to_epoch() {
  local s="${1:-}"
  s="${s//$'\r'/}"
  s="${s//$'\n'/}"
  if [[ -z "$s" || "$s" == "null" ]]; then
    echo 0
    return
  fi
  local try="$s"
  if [[ "$try" != *"T"* ]]; then
    try="${try/ /T}"
  fi
  local out
  out=$(date -u -d "$try" +%s 2>/dev/null) || out=$(date -d "$s" +%s 2>/dev/null) || out=0
  echo "${out:-0}"
}

file_sync_compute_status() {
  local diff_ok="$1"
  local repo_e="${2:-0}"
  local local_e="${3:-0}"
  local last_sync_e="${4:-0}"
  local now_e="${5:-0}"

  [[ -z "$repo_e" ]] && repo_e=0
  [[ -z "$local_e" ]] && local_e=0
  [[ -z "$last_sync_e" ]] && last_sync_e=0
  [[ -z "$now_e" ]] && now_e=0

  if [[ "$last_sync_e" -gt 0 ]] && [[ "$repo_e" -gt "$last_sync_e" ]] && [[ "$local_e" -gt "$last_sync_e" ]] && [[ "$diff_ok" -eq 0 ]]; then
    echo "conflict"
    return
  fi

  if [[ "$diff_ok" -eq 1 ]] && [[ "$now_e" -ge "$repo_e" ]] && [[ "$now_e" -ge "$local_e" ]] && [[ "$repo_e" -gt 0 ]] && [[ "$local_e" -gt 0 ]]; then
    echo "synced"
    return
  fi

  if [[ "$repo_e" -gt "$local_e" ]]; then
    echo "sync_required"
    return
  fi

  if [[ "$local_e" -gt "$repo_e" ]]; then
    if [[ "$last_sync_e" -eq 0 ]] || [[ "$last_sync_e" -lt "$local_e" ]]; then
      echo "local_newer"
      return
    fi
  fi

  if [[ "$diff_ok" -eq 0 ]]; then
    echo "sync_required"
    return
  fi

  echo "synced"
}

file_sync_status_color() {
  local st="$1"
  case "$st" in
    synced) printf '%s' $'\033[0;32m' ;;
    sync_required) printf '%s' $'\033[1;33m' ;;
    local_newer) printf '%s' $'\033[0;36m' ;;
    conflict) printf '%s' $'\033[0;31m' ;;
    detached) printf '%s' $'\033[0;35m' ;;
    error_*) printf '%s' $'\033[0;31m' ;;
    *) printf '%s' $'\033[0;37m' ;;
  esac
}

file_sync_color_reset() {
  printf '%s' $'\033[0m'
}

# Update one row in .filesync/files.json by local_path.
# Args: files_json_path project_root local_path full_master_path sync_status
filesync_write_file_row() {
  local files_path="$1"
  local project_root="$2"
  local local_path="$3"
  local full_master="$4"
  local sync_status_val="${5:-synced}"

  local now_iso
  now_iso=$(file_sync_now_iso)
  local full_local="$project_root/$local_path"
  local repo_iso
  local local_iso
  repo_iso=$(file_sync_mtime_iso "$full_master")
  local_iso=$(file_sync_mtime_iso "$full_local")

  jq --arg lp "$local_path" \
    --arg now "$now_iso" \
    --arg rs "${repo_iso:-}" \
    --arg ls "${local_iso:-}" \
    --arg st "$sync_status_val" \
    'map(
      if .local_path == $lp then
        . + {
          last_sync_at: $now,
          last_check_at: $now,
          sync_status: $st,
          repo_file_modified_at: (if $rs == "" then null else $rs end),
          local_file_modified_at: (if $ls == "" then null else $ls end)
        }
      else . end
    )' "$files_path" > "${files_path}.tmp"
  mv "${files_path}.tmp" "$files_path"
}
