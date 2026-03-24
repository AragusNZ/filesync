#!/usr/bin/env bash
# Shared FILE-SYNC marker helpers (sourced; no set -e at top level).

has_any_file_sync_marker() {
  local file="$1"
  grep -q ">> FILE-SYNC" "$file"
}

has_master_file_sync_marker() {
  local file="$1"
  grep -q ">> FILE-SYNC: MASTER" "$file"
}

has_clone_file_sync_marker() {
  local file="$1"
  grep -q ">> FILE-SYNC: CLONE" "$file"
}

has_uncoupled_clone_file_sync_marker() {
  local file="$1"
  grep -q ">> FILE-SYNC: CLONE (uncoupled)" "$file"
}

replace_clone_with_uncoupled_marker() {
  local file="$1"
  if ! has_clone_file_sync_marker "$file"; then
    return 1
  fi
  if has_uncoupled_clone_file_sync_marker "$file"; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  sed -E 's#// >> FILE-SYNC: CLONE \([^)]*\)#// >> FILE-SYNC: CLONE (uncoupled)#g' "$file" > "$tmp"
  mv "$tmp" "$file"
  return 0
}

render_master_marker_file() {
  local input_file="$1"
  local output_file="$2"

  if has_clone_file_sync_marker "$input_file"; then
    sed -E 's#// >> FILE-SYNC: CLONE \([^)]*\)#// >> FILE-SYNC: MASTER#g' "$input_file" > "$output_file"
    return 0
  fi

  if has_master_file_sync_marker "$input_file"; then
    cp "$input_file" "$output_file"
    return 0
  fi

  if has_any_file_sync_marker "$input_file"; then
    awk '
      BEGIN { updated = 0 }
      {
        if (updated == 0 && index($0, ">> FILE-SYNC") > 0) {
          print "// >> FILE-SYNC: MASTER"
          updated = 1
          next
        }
        print
      }
    ' "$input_file" > "$output_file"
    return 0
  fi

  return 1
}

render_clone_from_master_file() {
  local master_file="$1"
  local master_repo_path="$2"
  local repo_name="$3"
  local output_file="$4"

  sed "s#// >> FILE-SYNC: MASTER#// >> FILE-SYNC: CLONE ($master_repo_path from $repo_name)#" "$master_file" > "$output_file"
}

render_uncoupled_marker_file() {
  local input_file="$1"
  local output_file="$2"
  local repo_file_path="${3:-}"
  local repo_name="${4:-}"
  local marker_text="// >> FILE-SYNC: UNCOUPLED"

  if [[ -n "$repo_file_path" && -n "$repo_name" ]]; then
    marker_text="// >> FILE-SYNC: UNCOUPLED ($repo_file_path from $repo_name)"
  fi

  if has_any_file_sync_marker "$input_file"; then
    awk -v marker="$marker_text" '
      BEGIN { updated = 0 }
      {
        if (updated == 0 && index($0, ">> FILE-SYNC") > 0) {
          print marker
          updated = 1
          next
        }
        print
      }
    ' "$input_file" > "$output_file"
    return 0
  fi

  return 1
}

strip_file_sync_marker_lines() {
  local input_file="$1"
  local output_file="$2"
  awk 'index($0, ">> FILE-SYNC") == 0 { print }' "$input_file" > "$output_file"
}
