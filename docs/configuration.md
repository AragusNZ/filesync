# filesync configuration

## `.filesync/` files

All three are **JSON** files with a **`.json`** extension (`config.json`, `repos.json`, `files.json`). Basenames are centralized in `lib/data-names.sh`.

### `config.json`

A single JSON object. It is **shallow-merged** over `share/defaults/config.default.json` (package defaults). User keys win on conflicts.

- If you set `enabled` (boolean), it is normalized to `file_sync_enabled` when building runtime state.
- **`path_mode`**: `"relative"` (default) or `"absolute"`.
  - **relative**: each repo’s `path` in `repos` is resolved under the project root.
  - **absolute**: `path` is used as a filesystem path as-is (must exist as a directory).
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

Optional **`marker_style`** per row overrides comment wrapping for that path when the tool must emit a marker line without an existing comment wrapper on the line (rare). Allowed values: **`line_slash`** (`//`), **`line_hash`** (`#`), **`line_dash`** (`--`), **`block_c`** (`/* … */` on one line), **`html`** (`<!-- … -->`). If omitted, style is inferred from the file extension or basename (e.g. `Dockerfile` → hash, `.vue` / `.html` → html, `.css` → block, `.sql` → dash; unknown extension defaults to **`line_hash`**).

### Sync markers (text files)

Each synced copy carries a single-line **marker** containing the substring **`filesync:sync`** and a **`kind=`** field:

- **`kind=master`** — file in the upstream repo (source of truth).
- **`kind=clone`** — coupled local copy; includes **`path=…`** (repo-relative path) and **`repo=…`** (repo name).
- **`kind=detached`** — local file after **`detach`**; optional **`path=`** / **`repo=`** for context.

The tool rewrites the first marker line when syncing or changing coupling; the **comment style** around that payload matches the source file (or `marker_style` / extension rules above). Standard **`.json`** does not allow comments; use a commented dialect (e.g. JSONC) and map extension/basename, or avoid markers inside strict JSON.

### Writes

Commands such as `check` update:

- Row-level fields in `.filesync/files.json`
- `last_check_at` in `.filesync/config.json`

They do **not** rewrite a single monolithic config file at the project root.

## Project discovery

1. If `FILESYNC_PROJECT_ROOT` is set: that directory is the project root; `.filesync` defaults to `$PROJECT_ROOT/.filesync` unless `FILESYNC_DIR` is set.
2. If only `FILESYNC_DIR` is set: that path is the `.filesync` directory; project root is its parent.
3. Otherwise: from `cwd`, walk up until a directory `D` exists where **`D/.filesync`** is present; **`D` is the project root** (the directory that *contains* the `.filesync` directory, not its parent).

### `filesync init`

**`filesync init`** (optional path; default: current directory) creates **`<dir>/.filesync/`** with `config.json` (copied from package defaults), `repos.json`, and `files.json` (empty arrays). It does **not** walk parents — the directory you pass (or `cwd`) is the project root you are establishing. Other commands then find that root when your shell is under that tree (or via `FILESYNC_PROJECT_ROOT`). If **all three** JSON files already exist, `init` exits with an error; if only some exist, it creates whichever files are still missing.

### Enable / disable

**`filesync enable`** and **`filesync disable`** set **`file_sync_enabled`** in `.filesync/config.json` (`enable` asks for **y/N** confirmation; `disable` does not). While disabled, **`filesync check`** and **`filesync sync`** print a short message and exit with status **0** without updating or syncing files.

## Assembled state

Internally, commands build a **temporary** JSON file (merged top-level config + `repos` + `files`) using **`jq --slurpfile`** so large `files` arrays are not passed through shell arguments.

## Repo metadata (`repo-edit`)

**`filesync repo-edit <repo_name>`** updates **`repos.json`**. Pass any of **`--rename=new_name`**, **`--path=...`**, **`--url=...`**, **`--branch=...`** (at least one required). Renaming a repo rewrites **`repo_name`** on every row in **`files.json`** that referenced the old name. Use **`--branch=`** to change the configured branch.

## `check` / `sync` / `repos` / `list` filters

- **`--repo=name`**: for **`check`**, **`sync`**, and **`list`**, only rows (or repos) where `repo_name` equals this name. For **`repos`**, show only that repo’s entry.
- **`--file=fragment`**: for **`check`**, **`sync`**, and **`list`**, only rows where `local_path` **or** `repo_file_path` contains the fragment (substring / “like” match). Whitespace is trimmed from the fragment; an empty value matches all rows. Not valid for **`repos`**.

**`attach`**: re-couples rows with `sync_status: detached` by rewriting the local file from master (clone marker), clearing `sync_status`, then running **`check`** for that repo and path so status is recomputed.

## `sync` behavior and flags

By default, **`sync`** only processes rows whose **`sync_status`** is empty/unset or **`sync_required`**. Rows with **`sync_status: detached`** are skipped unless **`--include-detached`** is set.

- **`--dry-run`**: report what would be copied; do not write files or update `files.json`.
- **`--force`**: if the local file exists but lacks the **`filesync:sync kind=clone`** marker, sync anyway (default is to skip those paths).
- **`--all`**: include every row that passes repo/file filters and is not detached (unless **`--include-detached`**); still requires master/clone marker rules unless **`--force`** applies to clone-less locals.
- **`--include-status=a,b`**: comma-separated list of additional **`sync_status`** values to treat as eligible (whitespace around tokens is stripped).
- **`--include-detached`**: allow rows with **`sync_status: detached`** to be synced.

Master files must contain **`filesync:sync kind=master`** or the row is skipped (with a warning), regardless of other flags.

## Dependencies

`jq` is required. **`git`** must be on `PATH` for: `check`, `sync`, `list`, `add`, `add-master`, `push`, `detach`, `attach`, `rm`, and `repo-edit` (the shared runtime checks for `git` even when a given command does not invoke it). Other commands (`init`, `update`, `enable`, `disable`, `repo`) only require `jq` (and `curl` or `wget` for `update` when fetching release metadata or assets).
