#!/usr/bin/env bash
# Sourced by tests/lib/*.sh — not run directly.
# Prereqs: ROOT set to repo root; orchestrator sets LIB_TEST_TMP (shared temp dir, cleaned on exit).

: "${ROOT:?ROOT must be set}"
: "${LIB_TEST_TMP:?LIB_TEST_TMP must be set by run-lib-tests.sh}"

fail=0
ok() { echo "  lib ok: $*"; }
bad() {
	echo "  lib FAIL: $*" >&2
	# shellcheck disable=SC2034
	fail=1
}
