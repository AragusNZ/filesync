#!/usr/bin/env bash
# TTY progress on stderr for large file loops.
# Merged CONFIG_FILE sets .progress_display to hidden | bar | percent (default percent).
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
    if jq -e '.progress_display == "hidden"' "$CONFIG_FILE" &>/dev/null; then
      return 1
    fi
  fi
  return 0
}

filesync_progress_begin() {
  FILESYNC_PROGRESS_TOTAL="${1:?}"
  FILESYNC_PROGRESS_ACTIVE=1
  FILESYNC_PROGRESS_STYLE="percent"
  if [[ -n "${CONFIG_FILE:-}" ]] && [[ -f "$CONFIG_FILE" ]]; then
    FILESYNC_PROGRESS_STYLE="$(jq -r '.progress_display // "percent"' "$CONFIG_FILE")"
  fi
  case "$FILESYNC_PROGRESS_STYLE" in
    bar | percent) ;;
    *) FILESYNC_PROGRESS_STYLE=percent ;;
  esac
}

# Emit progress text only (no TTY controls); for tests and reuse.
# Uses FILESYNC_PROGRESS_STYLE (set by filesync_progress_begin), else percent.
# Args: current total
filesync_progress_format_line() {
  local current="${1:?}" total="${2:?}"
  local style="${FILESYNC_PROGRESS_STYLE:-percent}"
  case "$style" in
    bar) _filesync_progress_format_bar "$current" "$total" ;;
    percent) _filesync_progress_format_percent "$current" "$total" ;;
    *) _filesync_progress_format_percent "$current" "$total" ;;
  esac
}

_filesync_progress_format_percent() {
  local current="${1:?}" total="${2:?}"
  local pct=$((current * 100 / total))
  if ((current >= total)); then
    pct=100
  elif ((current > 0 && pct == 0)); then
    pct=1
  fi
  # Fixed 8-column token so width does not vary by digit count (1–100).
  printf '[ %3d%% ]' "$pct"
}

_filesync_progress_format_bar() {
  local current="${1:?}" total="${2:?}"
  local cols="${COLUMNS:-80}"
  ((cols >= 40)) || cols=40
  local bar_w=$((cols - 25))
  ((bar_w < 10)) && bar_w=10
  ((bar_w > 40)) && bar_w=40
  local filled=$((current * bar_w / total))
  ((filled > bar_w)) && filled=$bar_w
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
  printf '\r\033[K%s ' "$(filesync_progress_format_line "$current" "$total")" >&2
}

filesync_progress_end() {
  [[ "${FILESYNC_PROGRESS_ACTIVE:-0}" -eq 1 ]] || return 0
  printf '\n' >&2
  FILESYNC_PROGRESS_ACTIVE=0
}
