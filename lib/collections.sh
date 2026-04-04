#!/usr/bin/env bash
# Repo collections (.filesync/collections.json) and --also token expansion.

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data-names.sh"

# True (exit 0) if collections file exists and contains an object with .name == $name.
filesync_collections_has_name() {
  local coll_path="$1" name="$2"
  [[ -f "$coll_path" ]] || return 1
  jq -e --arg n "$name" 'type == "array" and any(.name == $n)' "$coll_path" &>/dev/null
}

# True if any collection uses this name.
filesync_collections_name_taken() {
  local coll_path="$1" name="$2"
  [[ -f "$coll_path" ]] || return 1
  jq -e --arg n "$name" 'type == "array" and any(.name == $n)' "$coll_path" &>/dev/null
}

# Add repo to one collection. Atomic write. Fails if duplicate member or validation fails.
# Args: collections_json_path repos_json_path collection_name repo_name
filesync_collection_add_repo() {
  local coll_path="$1" repos_path="$2" cname="$3" rname="$4"
  local tmp
  if [[ ! -f "$coll_path" ]]; then
    echo "filesync: collections file not found: $coll_path" >&2
    return 1
  fi
  if ! jq -e 'type == "array"' "$coll_path" &>/dev/null; then
    echo "filesync: $coll_path must be a JSON array" >&2
    return 1
  fi
  if ! jq -e --arg n "$cname" 'any(.name == $n)' "$coll_path" &>/dev/null; then
    echo "filesync: no collection named '$cname'" >&2
    return 1
  fi
  if ! jq -e --arg n "$rname" 'any(.name == $n)' "$repos_path" &>/dev/null; then
    echo "filesync: repo '$rname' not found in repos.json" >&2
    return 1
  fi
  if jq -e --arg c "$cname" --arg r "$rname" '.[] | select(.name == $c) | .repos | index($r) != null' "$coll_path" &>/dev/null; then
    echo "filesync: repo '$rname' already in collection '$cname'" >&2
    return 1
  fi
  tmp="$(mktemp)"
  if ! jq --arg c "$cname" --arg r "$rname" 'map(if .name == $c then .repos += [$r] else . end)' "$coll_path" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$coll_path"
}

# Remove repo from one collection. Idempotent if repo not listed. Atomic write.
# Args: collections_json_path collection_name repo_name
filesync_collection_remove_repo() {
  local coll_path="$1" cname="$2" rname="$3"
  local tmp
  if [[ ! -f "$coll_path" ]]; then
    echo "filesync: collections file not found: $coll_path" >&2
    return 1
  fi
  if ! jq -e --arg n "$cname" 'any(.name == $n)' "$coll_path" &>/dev/null; then
    echo "filesync: no collection named '$cname'" >&2
    return 1
  fi
  tmp="$(mktemp)"
  if ! jq --arg c "$cname" --arg r "$rname" 'map(if .name == $c then .repos |= map(select(. != $r)) else . end)' "$coll_path" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$coll_path"
}

# Remove repo from every collection; drop collections whose repos become empty.
# Args: collections_json_path repo_name
filesync_collections_prune_repo() {
  local coll_path="$1" rname="$2"
  local tmp before after
  [[ -f "$coll_path" ]] || return 0
  if ! jq -e 'type == "array"' "$coll_path" &>/dev/null; then
    return 0
  fi
  before=$(jq 'length' "$coll_path")
  tmp="$(mktemp)"
  if ! jq --arg r "$rname" 'map(.repos |= map(select(. != $r)) | select((.repos | length) > 0))' "$coll_path" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  after=$(jq 'length' "$tmp")
  mv "$tmp" "$coll_path"
  if [[ "$before" -gt "$after" ]]; then
    echo "filesync: removed empty collection(s) from collections.json after dropping repo '$rname'" >&2
  fi
}

# Expand comma-separated tokens into repo names (stdout, one per line, order-preserving unique).
# Same rules as --also=: each token is a global repo name or a collection name (expanded to .repos).
# Args: raw_csv repos_json_path collections_json_path
filesync_resolve_repo_tokens_to_repos() {
  filesync_also_expand_repos "$@"
}

# Expand --also CSV into repo names (stdout, one per line, order-preserving unique).
# Args: raw_csv repos_json_path collections_json_path
filesync_also_expand_repos() {
  local raw="$1" repos_path="$2" coll_path="$3"
  declare -a toks=()
  local line tokens_json coll_json

  if [[ -z "$raw" ]]; then
    return 0
  fi

  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "$line" ]] && continue
    toks+=("$line")
  done < <(echo "$raw" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | awk '!seen[$0]++')

  if [[ ${#toks[@]} -eq 0 ]]; then
    return 0
  fi

  tokens_json=$(printf '%s\n' "${toks[@]}" | jq -R . | jq -s -c .)

  if [[ -f "$coll_path" ]] && jq -e 'type == "array"' "$coll_path" &>/dev/null; then
    coll_json=$(cat "$coll_path")
  else
    coll_json='[]'
  fi

  local out
  if ! out=$(jq -r -n \
    --argjson tokens "$tokens_json" \
    --argjson colls "$coll_json" \
    --slurpfile rp "$repos_path" \
    '
    ($rp[0]) as $repos |
    if ($repos | type) != "array" then error("repos.json must be a JSON array") else
    def is_repo($n): any($repos[]?; .name == $n);
    $tokens[] | . as $t |
    ($colls | map(select(.name == $t)) | .[0]) as $c |
    if $c != null then
      if ($c.repos | type) != "array" then error("collection \($t) has invalid repos")
      elif ($c.repos | length) == 0 then error("collection \($t) has no repos (cannot use with --also)")
      else $c.repos[] end
    elif is_repo($t) then $t
    else error("unknown name \($t): not a repo in repos.json or a collection in collections.json")
    end
    end
    '); then
    return 1
  fi
  [[ -z "$out" ]] || printf '%s\n' "$out" | awk '!seen[$0]++'
}

# Fill named array with expanded repo names. $4 = array name (nameref). Returns 1 on error.
filesync_also_expand_to_array() {
  local raw="$1" repos_path="$2" coll_path="$3"
  # shellcheck disable=SC2178
  local -n _also_arr="${4:?}"
  local tmp
  _also_arr=()
  [[ -z "$raw" ]] && return 0
  tmp="$(mktemp)"
  if ! filesync_also_expand_repos "$raw" "$repos_path" "$coll_path" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mapfile -t _also_arr < "$tmp"
  rm -f "$tmp"
}
