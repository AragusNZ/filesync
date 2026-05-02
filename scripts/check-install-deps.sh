#!/usr/bin/env bash
# Verify runtime commands exist before `make install` (skipped when DESTDIR is set).
set -euo pipefail

missing=()

need_cmd() {
	local c="$1"
	if ! command -v "$c" >/dev/null 2>&1; then
		missing+=("$c")
	fi
}

need_cmd bash
need_cmd jq
need_cmd git
need_cmd flock

if [[ ${#missing[@]} -eq 0 ]]; then
	exit 0
fi

cat >&2 <<EOF
filesync install: missing required command(s): ${missing[*]}

Install on Debian/Ubuntu, for example:
  sudo apt update && sudo apt install -y jq git util-linux

bash is normally already installed; flock comes from the util-linux package.

On Fedora/RHEL:
  sudo dnf install -y jq git util-linux

On macOS (Homebrew):
  brew install jq git
  (flock is available by default on recent macOS.)

Then run make install again.
EOF
exit 1
