#!/usr/bin/env bash
# TTY progress bar on stderr for large file loops.
# Optional: merged CONFIG_FILE may set .show_progress to false.
# Disable entirely: FILESYNC_NO_PROGRESS=1

FILESYNC_PROGRESS_THRESHOLD=10

# Args: total item count
filesync_progress_want() {
  local total="${1:-0}"
  [[ "$total" =~ ^[0-9]+$ ]] || return 1
  (( total >= FILESYNC_PROGRESS_THRESHOLD )) || return 1
  [[ -t 2 ]] || return 1
  [[ "${FILESYNC_NO_PROGRESS:-}" == "1" ]] && return 1
  if [[ -n "${CONFIG_FILE:-}" ]] && [[ -f "$CONFIG_FILE" ]]; then
    if jq -e '.show_progress == false' "$CONFIG_FILE" &>/dev/null; then
      return 1
    fi
  fi
  return 0
}

filesync_progress_begin() {
  FILESYNC_PROGRESS_TOTAL="${1:?}"
  FILESYNC_PROGRESS_ACTIVE=1
}

# Emit bar text only (no TTY controls); for tests and reuse.
# Args: current total
filesync_progress_format_line() {
  local current="${1:?}" total="${2:?}"
  local cols="${COLUMNS:-80}"
  (( cols >= 40 )) || cols=40
  local bar_w=$((cols - 25))
  (( bar_w < 10 )) && bar_w=10
  (( bar_w > 40 )) && bar_w=40
  local filled=$((current * bar_w / total))
  (( filled > bar_w )) && filled=$bar_w
  local empty=$((bar_w - filled))
  local bar="" j
  for ((j = 0; j < filled; j++)); do bar+="#"; done
  for ((j = 0; j < empty; j++)); do bar+="·"; done
  printf '[%s] %d/%d' "$bar" "$current" "$total"
}

# Args: current (1-based index)
filesync_progress_update() {
  [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]] || return 0
  [[ -t 2 ]] || return 0
  local current="${1:?}" total="${FILESYNC_PROGRESS_TOTAL:?}"
  printf '\r\033[K%s' "$(filesync_progress_format_line "$current" "$total")" >&2
}

filesync_progress_end() {
  [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]] || return 0
  printf '\n' >&2
  FILESYNC_PROGRESS_ACTIVE=0
}
