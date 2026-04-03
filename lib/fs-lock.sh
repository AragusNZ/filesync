#!/usr/bin/env bash
# Serialize writers to the global filesync metadata directory.

# Acquire exclusive lock on $FILESYNC_SYSTEM_HOME/.lock (call once per process).
# Uses FD 9; pair with filesync_global_lock_release on EXIT trap.
filesync_global_lock_acquire() {
  local home="${FILESYNC_SYSTEM_HOME:?}"
  mkdir -p "$home"
  touch "$home/.lock"
  exec {FILESYNC_GLOBAL_LOCK_FD}>>"$home/.lock"
  flock "$FILESYNC_GLOBAL_LOCK_FD"
}

filesync_global_lock_release() {
  if [[ -n "${FILESYNC_GLOBAL_LOCK_FD:-}" ]]; then
    flock -u "$FILESYNC_GLOBAL_LOCK_FD" 2>/dev/null || true
    eval "exec ${FILESYNC_GLOBAL_LOCK_FD}>&-" 2>/dev/null || true
    unset FILESYNC_GLOBAL_LOCK_FD
  fi
}
