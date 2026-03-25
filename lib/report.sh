#!/usr/bin/env bash
# Shared report helpers for command summaries (sourced).

# Increment an associative-array counter by key.
# Usage: filesync_counts_inc COUNTS_ASSOC_NAME "key"
filesync_counts_inc() {
  local assoc_name="$1"
  local key="${2:-unset}"
  [[ -z "$key" ]] && key="unset"
  # shellcheck disable=SC2178,SC2034
  declare -n _filesync_counts_ref="$assoc_name"
  local cur="${_filesync_counts_ref[$key]:-0}"
  _filesync_counts_ref["$key"]=$((cur + 1))
}

# Render associative-array counters as "k=v" pairs in key-sorted order.
# Usage: filesync_counts_render_kv COUNTS_ASSOC_NAME
filesync_counts_render_kv() {
  local assoc_name="$1"
  # shellcheck disable=SC2178,SC2034
  declare -n _filesync_counts_ref="$assoc_name"

  local key out=""
  while IFS= read -r key; do
    [[ -n "$out" ]] && out+=" "
    out+="${key}=${_filesync_counts_ref[$key]}"
  done < <(printf '%s\n' "${!_filesync_counts_ref[@]}" | sort)

  printf '%s' "$out"
}

# Print one status summary line to stderr.
# Usage: filesync_print_status_summary "rows updated" "$count" COUNTS_ASSOC_NAME
filesync_print_status_summary() {
  local label="$1"
  local total="$2"
  local assoc_name="$3"
  local kv
  kv="$(filesync_counts_render_kv "$assoc_name")"
  if [[ -z "$kv" ]]; then
    echo "Status summary (${label}: ${total}): none" >&2
    return
  fi
  echo "Status summary (${label}: ${total}): ${kv}" >&2
}
