#!/usr/bin/env bash
# Stage make install and run the symlinked binary against a minimal .filesync project.
set -euo pipefail
ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

smoke_one() {
  local label="$1" dest="$2" prefix="$3"
  make -C "${ROOT}" install DESTDIR="${dest}" PREFIX="${prefix}"
  export PATH="${dest}${prefix}/bin:${PATH}"
  mkdir -p "${TMP}/proj-${label}"
  cd "${TMP}/proj-${label}"
  filesync init
  filesync help | grep -q 'filesync'
  filesync check >/dev/null
  filesync --version | grep -q 'filesync'
}

smoke_one local "${TMP}/stage-local" /usr/local
smoke_one usr "${TMP}/stage-usr" /usr
