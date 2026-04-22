#!/usr/bin/env bash
# stderr formatting for filesync doctor inspect (sourced; no set -e at top level).
# Requires: lib/colors.sh

filesync_doctor_summary_reset() {
  FILESYNC_DOCTOR_WARN_COUNT=0
  FILESYNC_DOCTOR_NOTE_COUNT=0
}

filesync_doctor_title() {
  echo -e "${BOLD}${WHITE}filesync doctor inspect${NC}" >&2
  echo "" >&2
}

filesync_doctor_section() {
  echo -e "${CYAN}--- $1 ---${NC}" >&2
}

filesync_doctor_subsection() {
  echo -e "  ${WHITE}$*${NC}" >&2
}

# Informational line (does not bump counters).
filesync_doctor_info() {
  echo -e "  ${GRAY}$*${NC}" >&2
}

filesync_doctor_warn_msg() {
  FILESYNC_DOCTOR_WARN_COUNT=$(( ${FILESYNC_DOCTOR_WARN_COUNT:-0} + 1 ))
  echo -e "  ${YELLOW}$*${NC}" >&2
}

filesync_doctor_note_msg() {
  FILESYNC_DOCTOR_NOTE_COUNT=$(( ${FILESYNC_DOCTOR_NOTE_COUNT:-0} + 1 ))
  echo -e "  ${YELLOW}$*${NC}" >&2
}

filesync_doctor_detail() {
  echo -e "    ${GRAY}$*${NC}" >&2
}

filesync_doctor_summary_print() {
  echo "" >&2
  local w n
  w="${FILESYNC_DOCTOR_WARN_COUNT:-0}"
  n="${FILESYNC_DOCTOR_NOTE_COUNT:-0}"
  if [[ "$w" -eq 0 && "$n" -eq 0 ]]; then
    echo -e "${GREEN}Summary: no warnings or notes.${NC}" >&2
  else
    echo -e "${WHITE}Summary:${NC} ${w} warning(s), ${n} note(s)." >&2
  fi
}
