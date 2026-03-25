#!/usr/bin/env bash
# Sourced by tests/commands/*.sh — not run directly.
# Prereqs (export from run-command-tests.sh): ROOT, TMP, EXPECTED_VERSION, PATH must include staged filesync.

: "${ROOT:?ROOT must be set}"
: "${TMP:?TMP must be set}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION must be set}"

die() {
	echo "FAIL: $*" >&2
	exit 1
}
