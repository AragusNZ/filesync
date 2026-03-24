# filesync configuration

## `.filesync/` files

All three are **JSON** files with a **`.json`** extension (`config.json`, `repos.json`, `files.json`). Basenames are centralized in `lib/data-names.sh`.

### `config.json`

A single JSON object. It is **shallow-merged** over `share/defaults/config.default.json` (package defaults). User keys win on conflicts.

- If you set `enabled` (boolean), it is normalized to `file_sync_enabled` when building runtime state.
- **`path_mode`**: `"relative"` (default) or `"absolute"`.
  - **relative**: each repo’s `path` in `repos` is resolved under the project root.
  - **absolute**: `path` is used as a filesystem path as-is (must exist as a directory).
- Optional keys used by sync/check (see default JSON): `scripts_local_directory`, `scripts_repo_directory`, `scripts_repo`, `exclude_scripts`, etc.

Avoid deep nesting in `config.json` unless you document a merge policy; the merge is **one level** (`jq` `*`).

### `repos.json`

JSON **array** of objects, for example:

```json
[
  {
    "name": "api",
    "url": "git@example.com:org/api.git",
    "path": "../api",
    "branch": "main"
  }
]
```

### `files.json`

JSON **array** of file row objects (paths, `repo_name`, `sync_status`, marker-related fields, mtimes, etc.).

### Writes

Commands such as `check` update:

- Row-level fields in `.filesync/files.json`
- `last_check_at` in `.filesync/config.json`

They do **not** rewrite a single monolithic config file at the project root.

## Project discovery

1. If `FILESYNC_PROJECT_ROOT` is set: that directory is the project root; `.filesync` defaults to `$PROJECT_ROOT/.filesync` unless `FILESYNC_DIR` is set.
2. If only `FILESYNC_DIR` is set: that path is the `.filesync` directory; project root is its parent.
3. Otherwise: from `cwd`, walk up until a directory containing `.filesync` exists; that parent directory is the project root.

## Assembled state

Internally, commands build a **temporary** JSON file (merged top-level config + `repos` + `files`) using **`jq --slurpfile`** so large `files` arrays are not passed through shell arguments.

## Repo metadata (`repo-edit`)

**`filesync repo-edit <repo_name>`** updates **`repos.json`**. Pass any of **`--rename=new_name`**, **`--path=...`**, **`--url=...`**, **`--branch=...`** (at least one required). Renaming a repo rewrites **`repo_name`** on every row in **`files.json`** that referenced the old name. Use **`--branch=`** to change the configured branch.

## `check` / `sync` / `repos` / `list` filters

- **`--repo=name`**: for **`check`**, **`sync`**, and **`list`**, only rows (or repos) where `repo_name` equals this name. For **`repos`**, show only that repo’s entry.
- **`--file=fragment`** (**`check`** and **`sync`** only): only rows where `local_path` **or** `repo_file_path` contains the fragment (substring / “like” match). Whitespace is trimmed from the fragment; an empty value matches all rows.

**`attach`**: re-couples rows with `sync_status: uncoupled` by rewriting the local file from master (clone marker), clearing `sync_status`, then running **`check`** for that repo and path so status is recomputed.

## Dependencies

`jq` is required. Git is required for sync/push flows.
