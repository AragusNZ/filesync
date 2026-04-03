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

# Set FILESYNC_HOME, repo path anchor (for relative paths in repos.json), and replace global repos.json.
filesync_test_seed_global_repos() {
	local path_root="${1:?}"
	local repos_file="${2:?}"
	[[ -n "${FILESYNC_HOME:-}" ]] || {
		echo "filesync_test_seed_global_repos: FILESYNC_HOME unset" >&2
		return 1
	}
	[[ -f "$repos_file" ]] || {
		echo "filesync_test_seed_global_repos: missing repos file: $repos_file" >&2
		return 1
	}
	mkdir -p "$FILESYNC_HOME"
	local abs_root
	abs_root="$(cd "$path_root" && pwd)"
	export FILESYNC_REPO_PATH_ANCHOR="$abs_root"
	jq 'map((if (.id // "") == "" then . + {id: ("testid-" + .name)} else . end) | if (.merge_using_git | type) != "boolean" then . + {merge_using_git: false} else . end)' "$repos_file" >"${FILESYNC_HOME}/repos.json"
	if [[ ! -f "${FILESYNC_HOME}/system.json" ]]; then
		jq -n '{version: 2}' >"${FILESYNC_HOME}/system.json"
	else
		jq '.version = 2' "${FILESYNC_HOME}/system.json" >"${FILESYNC_HOME}/system.json.tmp"
		mv "${FILESYNC_HOME}/system.json.tmp" "${FILESYNC_HOME}/system.json"
	fi
	[[ -f "${FILESYNC_HOME}/collections.json" ]] || printf '%s\n' '[]' | jq . >"${FILESYNC_HOME}/collections.json"
}

# Concat global repos.json with another JSON array file (jq array + array).
filesync_test_append_global_repos() {
	local repos_file="${1:?}"
	[[ -n "${FILESYNC_HOME:-}" ]] || {
		echo "filesync_test_append_global_repos: FILESYNC_HOME unset" >&2
		return 1
	}
	[[ -f "${FILESYNC_HOME}/repos.json" ]] || {
		echo "filesync_test_append_global_repos: no global repos.json" >&2
		return 1
	}
	jq -s '.[0] + (.[1] | map((if (.id // "") == "" then . + {id: ("testid-" + .name)} else . end) | if (.merge_using_git | type) != "boolean" then . + {merge_using_git: false} else . end))' \
		"${FILESYNC_HOME}/repos.json" "$repos_file" >"${FILESYNC_HOME}/repos.json.tmp"
	mv "${FILESYNC_HOME}/repos.json.tmp" "${FILESYNC_HOME}/repos.json"
}
