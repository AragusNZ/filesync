#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${TESTS}/harness-lib.sh"
: "${fail:=0}"
# shellcheck source=/dev/null
source "${ROOT}/lib/collections.sh"

td="${LIB_TEST_TMP}/collections"
mkdir -p "$td"
repos="${td}/repos.json"
coll="${td}/collections.json"

printf '%s\n' '[{"name":"alpha","path":"x","url":"","branch":"main"},{"name":"beta","path":"y","url":"","branch":"main"}]' >"$repos"
printf '%s\n' '[{"name":"grp","repos":["alpha"]}]' >"$coll"

if filesync_collection_add_repo "$coll" "$repos" grp beta; then
	ok "collection_add_repo second member"
else
	bad "collection_add_repo second member"
fi

if filesync_collection_add_repo "$coll" "$repos" grp beta 2>/dev/null; then
	bad "collection_add_repo should reject duplicate"
else
	ok "collection_add_repo rejects duplicate"
fi

if filesync_collection_add_repo "$coll" "$repos" nosuch beta 2>/dev/null; then
	bad "collection_add_repo should reject missing collection"
else
	ok "collection_add_repo rejects missing collection"
fi

if filesync_collection_add_repo "$coll" "$repos" grp not_in_repos 2>/dev/null; then
	bad "collection_add_repo should reject unknown repo"
else
	ok "collection_add_repo rejects unknown repo"
fi

if filesync_collection_remove_repo "$coll" grp beta; then
	ok "collection_remove_repo"
else
	bad "collection_remove_repo"
fi

if filesync_collection_remove_repo "$coll" grp beta; then
	ok "collection_remove_repo idempotent"
else
	bad "collection_remove_repo idempotent"
fi

if filesync_collection_remove_repo "$coll" grp nosuch; then
	ok "collection_remove_repo idempotent missing repo name"
else
	bad "collection_remove_repo idempotent missing repo name"
fi

if filesync_collection_remove_repo "$coll" badname alpha 2>/dev/null; then
	bad "collection_remove_repo should reject missing collection"
else
	ok "collection_remove_repo rejects missing collection"
fi

_out=""
if _out=$(filesync_also_expand_repos "grp" "$repos" "$coll" 2>&1); then
	if [[ "$_out" == alpha ]]; then
		ok "also_expand collection token"
	else
		bad "also_expand collection token got '${_out}'"
	fi
else
	bad "also_expand collection token failed"
fi

if _out=$(filesync_also_expand_repos "alpha" "$repos" "$coll" 2>&1); then
	if [[ "$_out" == alpha ]]; then
		ok "also_expand plain repo"
	else
		bad "also_expand plain repo"
	fi
else
	bad "also_expand plain repo failed"
fi

printf '%s\n' '[{"name":"grp","repos":["alpha","beta"]}]' >"$coll"
if _out=$(filesync_also_expand_repos "alpha,grp" "$repos" "$coll" 2>&1); then
	# token alpha, then grp -> alpha,beta; order-preserving dedupe -> alpha newline beta
	if [[ "$_out" == $'alpha\nbeta' ]]; then
		ok "also_expand mixed dedupe order"
	else
		bad "also_expand mixed dedupe expected alpha+beta lines got '${_out//$'\n'/|}'"
	fi
else
	bad "also_expand mixed failed"
fi

if filesync_also_expand_repos "not_a_thing" "$repos" "$coll" 2>/dev/null; then
	bad "also_expand should fail unknown token"
else
	ok "also_expand unknown token"
fi

printf '%s\n' '[{"name":"emptyc","repos":[]}]' >"$coll"
if filesync_also_expand_repos "emptyc" "$repos" "$coll" 2>/dev/null; then
	bad "also_expand should fail empty collection"
else
	ok "also_expand empty collection"
fi

printf '%s\n' '[{"name":"grp","repos":["alpha"]}]' >"$coll"
declare -a _ar=()
if filesync_also_expand_to_array "" "$repos" "$coll" _ar; then
	if [[ ${#_ar[@]} -eq 0 ]]; then
		ok "also_expand_to_array empty raw"
	else
		bad "also_expand_to_array empty raw len=${#_ar[@]}"
	fi
else
	bad "also_expand_to_array empty raw failed"
fi

if filesync_also_expand_to_array "grp" "$repos" "$coll" _ar; then
	if [[ ${#_ar[@]} -eq 1 && "${_ar[0]}" == alpha ]]; then
		ok "also_expand_to_array"
	else
		bad "also_expand_to_array array wrong"
	fi
else
	bad "also_expand_to_array failed"
fi

printf '%s\n' '[{"name":"g1","repos":["alpha","beta"]},{"name":"g2","repos":["alpha"]}]' >"$coll"
if filesync_collections_prune_repo "$coll" alpha; then
	:
else
	bad "collections_prune_repo"
fi
if [[ "$(jq 'length' "$coll")" -eq 1 ]] && jq -e '.[0].name == "g1" and .[0].repos == ["beta"]' "$coll" >/dev/null; then
	ok "collections_prune_repo strips repo and drops empty collections"
else
	bad "collections_prune_repo expected one collection g1 with beta"
fi

if [[ "${fail}" -ne 0 ]]; then exit 1; fi
