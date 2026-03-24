#!/usr/bin/env bash
# External command checks (requires lib/colors.sh to be sourced first).

filesync_require_jq() {
  if ! command -v jq &>/dev/null; then
    # RED, NC from lib/colors.sh (always sourced before this file).
    # shellcheck disable=SC2154
    echo -e "${RED}Error: jq is required but not installed.${NC}" >&2
    exit 1
  fi
}
