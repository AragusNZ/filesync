#!/usr/bin/env bash
# Generate unique repo ids for global repos.json.

filesync_new_repo_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    tr -d '\r\n' </proc/sys/kernel/random/uuid
    return 0
  fi
  # Fallback: 128-bit hex (not RFC 4122, but unique enough for local ids)
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
    return 0
  fi
  # Last resort
  printf '%s-%s' "$(date +%s)" "$RANDOM$RANDOM"
}
