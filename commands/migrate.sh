#!/usr/bin/env bash
# Legacy per-project JSON import + upgrade global repos (ids) and all projects' files.json (repo_id).

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/cli-help.sh"
if filesync_argv_wants_help "$@"; then
  cat <<'EOF'
Usage: filesync migrate

Run from inside a filesync project. If .filesync/repos.json exists, merge its repos and
collections into the global store (see docs), back up under .filesync/legacy-backup/<ts>/,
then remove those legacy files.

Always ensures every global repo has a stable id and every known files.json row has repo_id.

EOF
  exit 0
fi
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/colors.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/log.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/data-names.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/deps.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/resolve.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/system-resolve.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/repo-id.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/fs-lock.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/paths.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/filesync-projects.sh"
# shellcheck source=/dev/null
source "$_CMD_ROOT/../lib/repos-json.sh"

filesync_resolve_or_exit
filesync_require_files
filesync_require_jq

LEGACY_REPOS="${FILESYNC_DIR}/${FILESYNC_REPOS_NAME}"
LEGACY_COLL="${FILESYNC_DIR}/${FILESYNC_COLLECTIONS_NAME}"
LEGACY_CFG="${FILESYNC_DIR}/${FILESYNC_CONFIG_NAME}"

FILESYNC_SYSTEM_HOME="$(filesync_ensure_system_store)" || exit 1

G_REPOS="${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_REPOS_NAME}"
G_COLL="${FILESYNC_SYSTEM_HOME}/${FILESYNC_GLOBAL_COLLECTIONS_NAME}"

if [[ -f "$LEGACY_REPOS" ]]; then
  ts="$(date +%Y%m%d%H%M%S)"
  BK="${FILESYNC_DIR}/legacy-backup/${ts}"
  mkdir -p "$BK"
  cp -a "$LEGACY_REPOS" "$BK/"
  [[ -f "$LEGACY_COLL" ]] && cp -a "$LEGACY_COLL" "$BK/"
  [[ -f "$LEGACY_CFG" ]] && cp -a "$LEGACY_CFG" "$BK/"
  echo "filesync: previous project JSON backed up under $BK" >&2

  cs_json=true
  if [[ -f "$LEGACY_CFG" ]] && jq -e '.file_sync_enabled == false' "$LEGACY_CFG" &>/dev/null; then
    cs_json=false
  fi

  tmp_r="$(mktemp)"
  tmp_c=""
  cleanup() {
    rm -f "$tmp_r"
    [[ -n "${tmp_c:-}" ]] && rm -f "$tmp_c"
  }
  trap cleanup EXIT

  if ! jq -n \
    --argjson cs "$cs_json" \
    --slurpfile g "$G_REPOS" \
    --slurpfile l "$LEGACY_REPOS" '
    def norm:
      {name, url: (.url // null), path: (.path // null), branch: (.branch // "main")};
    ($g[0] // []) as $G |
    ($l[0] // []) as $L |
    reduce $L[] as $row ($G;
      (map(select(.name == $row.name)) | .[0] // null) as $ex |
      if $ex == null then
        . + [($row | norm) + {check_sync_enabled: $cs, mirror_in_enabled: true}]
      elif ($ex | norm) == ($row | norm) then
        .
      else
        error("repo \($row.name): global entry differs from project copy (path/url/branch)")
      end)
    ' >"$tmp_r"; then
    echo "filesync: repos merge failed. Restore from $BK if needed." >&2
    exit 1
  fi

  mv "$tmp_r" "$G_REPOS"

  if [[ -f "$LEGACY_COLL" ]] && jq -e 'type == "array"' "$LEGACY_COLL" &>/dev/null; then
    tmp_c="$(mktemp)"
    if ! jq -n \
      --slurpfile g "$G_COLL" \
      --slurpfile l "$LEGACY_COLL" '
      ($g[0] // []) as $G |
      ($l[0] // []) as $L |
      reduce $L[] as $c ($G;
        (map(select(.name == $c.name)) | .[0] // null) as $ex |
        if $ex == null then
          . + [$c]
        elif $ex == $c then
          .
        else
          error("collection \($c.name) exists globally with different definition")
        end)
      ' >"$tmp_c"; then
      echo "filesync: collections merge failed. Restore global repos from $BK if needed." >&2
      exit 1
    fi
    mv "$tmp_c" "$G_COLL"
    tmp_c=""
  fi

  rm -f "$LEGACY_REPOS" "$LEGACY_COLL" "$LEGACY_CFG"
  trap - EXIT
  echo -e "${GREEN}filesync: legacy project JSON merged into global store.${NC}" >&2
else
  echo "filesync: no project ${FILESYNC_REPOS_NAME} (legacy import skipped)." >&2
fi

filesync_global_lock_acquire
trap 'filesync_global_lock_release' EXIT

tmp_ids="$(mktemp)"
: >"$tmp_ids"
while IFS= read -r line; do
  if echo "$line" | jq -e '(.id // "") != ""' &>/dev/null; then
    echo "$line" >>"$tmp_ids"
  else
    nid="$(filesync_new_repo_id)"
    echo "$line" | jq --arg id "$nid" '. + {id: $id}' >>"$tmp_ids"
  fi
done < <(jq -c '.[]' "$G_REPOS")
jq -s '.' "$tmp_ids" >"${G_REPOS}.new"
mv "${G_REPOS}.new" "$G_REPOS"
rm -f "$tmp_ids"

if ! filesync_assert_global_repos_unique_names "$G_REPOS"; then
  echo "filesync: fix duplicate names in ${G_REPOS} and re-run migrate if needed." >&2
  exit 1
fi

rroot="$(filesync_read_repo_path_root "$FILESYNC_SYSTEM_HOME")"

_migrate_files_json() {
  local fp="$1"
  [[ -f "$fp" ]] || return 0
  local tmpf
  tmpf="$(mktemp)"
  if ! jq --slurpfile r "$G_REPOS" '
    ($r[0]) as $R
    | map(
        if (.repo_id // "") != "" and .repo_id != null then .
        else . + {repo_id: (($R[] | select(.name == .repo_name) | .id) // "")}
        end
      )' "$fp" >"$tmpf"; then
    rm -f "$tmpf"
    echo "filesync: could not upgrade $(basename "$fp")" >&2
    return 1
  fi
  mv "$tmpf" "$fp"
}

while IFS= read -r proot || [[ -n "${proot:-}" ]]; do
  [[ -z "$proot" ]] && continue
  _migrate_files_json "$proot/.filesync/${FILESYNC_FILES_NAME}"
done < <(
  { printf '%s\n' "$PROJECT_ROOT"; filesync_list_project_roots_from_global_store "$FILESYNC_SYSTEM_HOME" "$rroot" "$G_REPOS"; } | sort -u
)

_migrate_files_json "${FILESYNC_DIR}/${FILESYNC_FILES_NAME}"

filesync_global_lock_release
trap - EXIT

echo -e "${GREEN}filesync: migrate complete.${NC} Global store: $FILESYNC_SYSTEM_HOME" >&2
