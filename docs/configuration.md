# filesync configuration

## `.filesync/` files

All three are **JSON** files with a **`.json`** extension (`config.json`, `repos.json`, `files.json`). Basenames are centralized in `lib/data-names.sh`.

### `config.json`

A single JSON object. It is **shallow-merged** over `share/defaults/config.default.json` (package defaults). User keys win on conflicts.

- Only **`file_sync_enabled`** controls whether **`check`** / **`sync`** run; obsolete keys `enabled` and `show_progress` are ignored and stripped from the merged view used at runtime.
- **`path_mode`**: `"relative"` (default) or `"absolute"`.
  - **relative**: each repo’s `path` in `repos` is resolved under the project root.
  - **absolute**: `path` is used as a filesystem path as-is (must exist as a directory).
- **`progress_display`**: `"percent"` (default), `"bar"`, or `"hidden"`. Controls TTY progress on stderr for long `check` / `sync` / multi-file loops when stderr is a terminal and there are at least 10 items: **percent** prints `[NNN%]`; **bar** prints the filled bracket bar and counts; **hidden** turns progress off. Use **`filesync progress`** to show or set the value.
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

Each synced copy carries a single-line **marker** containing the substring **`filesync`** and a **`kind=`** field:

- **`kind=master`** — file in the upstream repo (source of truth).
- **`kind=clone`** — coupled local copy; includes **`path=…`** (repo-relative path) and **`repo=…`** (repo name).
- **`kind=detached`** — local file after **`detach-file`**; optional **`path=`** / **`repo=`** for context.

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

## Repo metadata (`edit-repo`)

**`filesync edit-repo <repo_name>`** updates **`repos.json`**. Pass any of **`--rename=new_name`**, **`--path=...`**, **`--url=...`**, **`--branch=...`** (at least one required). Renaming a repo rewrites **`repo_name`** on every row in **`files.json`** that referenced the old name, and updates the **`repo=`** field in the first **`filesync`** marker on each affected local file (clone or detached copies). Use **`--branch=`** to change the configured branch.

## Adding mappings (`add-file`, `add-master`, `add-clone`)

**`add-file`** tracks paths from a repo checkout into the project. The file under the repo must already contain a **`kind=master`** marker; **`kind=clone`** (or another non-master marker) is rejected. If the repo file has **no** filesync marker yet, pass **`--mark-master`** so the tool prepends a master marker (comment style follows the path).

**`add-master`** promotes local files into the master repo checkout and adds mappings; omit **`:path_in_repo`** when it matches **`local_path`**. See **`man filesync`** for arguments and **`--also`**.

**`add-clone`** creates a **`kind=clone`** copy and row in a **sibling** initialized project from a **`kind=master`** file that lives under the **current** project. If that source file has no filesync marker, a **`kind=master`** marker is prepended automatically; other non-master markers are rejected. This differs from **`add-file`**, where an unmarked repo file requires **`--mark-master`** explicitly.

## Removing mappings

- **`detach-file`** / **`detach-repo`**: the row stays in **`files.json`** with **`sync_status: detached`**; the local file’s marker becomes **`kind=detached`**. Use when you want to pause syncing but keep the mapping.
- **`remove-file`** (alias **`rmf`**): removes the row from **`files.json`** and strips **`kind=clone`** or **`kind=detached`** markers from the local file; **`kind=master`** in the repo checkout is unchanged. Pass **`--all-missing`** to also remove every mapping whose cached **`sync_status`** is **`error_missing_master`**, unioned with any explicit paths (similar to how **`push --all`** adds all **`local_newer`** rows). If only **`--all-missing`** is given and no rows match, the command exits **0** after a short message. Full syntax is in **`man filesync`**.
- **`remove-repo`**: removes a repo from **`repos.json`**; if **`files.json`** still references that repo, the command confirms, then removes each mapping like **`remove-file`**. See the next section.

## Removing a repo (`remove-repo`)

**`filesync remove-repo`** (alias **`rmr`**) drops an entry from **`repos.json`**. If **`files.json`** still has rows for that repo, the command asks for confirmation; if you confirm, each mapping is removed the same way as **`remove-file`** (row deleted; clone/detached markers stripped on disk; master marker kept), then the repo entry is removed. **`rmr -y`** or **`--yes`** skips the prompt. See **`man filesync`** for details.

## `check` / `sync` / `list-repos` / `list-files` filters

- **`--repo=name`**: for **`check`**, **`sync`**, and **`list-files`**, only rows where `repo_name` equals this name. For **`list-repos`**, show only that repo’s entry.
- **`--file=fragment`**: for **`check`**, **`sync`**, and **`list-files`**, only rows where `local_path` **or** `repo_file_path` contains the fragment (substring / “like” match). Whitespace is trimmed from the fragment; an empty value matches all rows. Not valid for **`list-repos`**.

**`attach-file`** (and **`attach-repo`**, which runs it for every row for a repo): re-couples rows with `sync_status: detached` by rewriting the local file from master (clone marker), clearing `sync_status`, then running **`check`** for that repo and path so status is recomputed. **`detach-repo`** runs **`detach-file`** for every mapping with that **`repo_name`**.

## Push (`push`)

**`filesync push`** writes local content to the master path in the linked repo (the inverse of copying from master during **`sync`**). Use **`filesync push [--all] [<local_path> …]`**: **`--all`** adds every mapping whose **`sync_status`** is **`local_newer`**, unioned with any paths you list. If **`--all`** is given with no paths and there are no **`local_newer`** rows, the command exits successfully after a short message. Full behavior is in **`man filesync`**.

## Cross-project mirroring (`--also`)

**`add-file`**, **`add-master`**, and **`add-clone`** accept **`--also=repo1,repo2`** to mirror mappings into sibling initialized projects.

- Each value is a repo name from the **current** project’s `.filesync/repos.json`.
- That repo’s configured **`path`** must point at a directory that is itself an initialized filesync project (it contains its own `.filesync/`).
- For each sibling project, filesync uses that sibling’s configuration (including **`path_mode`**) when resolving the master repo checkout.
- For `add-master --also` and `add-clone --also`, mirrored rows in sibling projects are initialized as **`sync_required`** so each project can run **`check`** / **`sync`** to compute timestamps and verify status in its own context.

## `sync` / `list-files` status filter (`--status`)

**`list-files`**: optional **`--status=a,b,...`** and optional **`--include-detached`** (with **`--status`** only). Omit **`--status`** to list every row (after **`--repo`** / **`--file`** filters).

**`sync`**: by default only rows whose **`sync_status`** is **unset**, **`sync_required`**, or **`error_missing_local`** are processed (so missing local files are recreated from master); **`detached`** rows are skipped unless **`--include-detached`** is set. Pass **`--status=`** to replace that default with other tokens.

Comma-separated tokens (whitespace around tokens is stripped). A row matches if **any** token matches (OR):

- **`unset`** — empty / missing **`sync_status`**
- **`all`** — every status **except** **`detached`**, unless **`--include-detached`** is set (then **`all`** includes **`detached`** too) or the list also contains the literal token **`detached`**
- **`error`** — any **`sync_status`** whose name starts with **`error_`**
- any other token — exact **`sync_status`** string (e.g. **`synced`**, **`local_newer`**, **`detached`**, **`error_repo_unavailable`**)

Examples: **`--status=all`** (all non-detached); **`--status=all --include-detached`** or **`--status=all,detached`** (include detached); **`--status=error`**; **`--status=sync_required,local_newer,synced`**.

## `sync` behavior and flags

- **`--check`**: run `filesync check` first with matching `--repo`, `--file`, and `--status` filters before syncing. If that preflight check fails, sync exits without copying.
- **`--include-detached`**: allow **`sync_status: detached`** rows when using the default status filter, or include them when **`--status=`** contains **`all`** (without adding the **`detached`** token).
- **`--dry-run`**: report what would be copied; do not write files or update `files.json`.
- **`--force`**: if the local file exists but lacks the **`filesync kind=clone`** marker, sync anyway (default is to skip those paths). When no **`--status`** filter is given, **`--force`** also selects **`local_newer`** and **`conflict`** rows so master replaces local.

Master files must contain **`filesync kind=master`** or the row is skipped (with a warning), regardless of other flags.

## Environment variables

- **`FILESYNC_PROJECT_ROOT`**: forces the project root (discovery does not walk parents); `.filesync` defaults to `$FILESYNC_PROJECT_ROOT/.filesync` unless `FILESYNC_DIR` is also set.
- **`FILESYNC_DIR`**: forces the `.filesync` directory path; project root becomes its parent.
- **`FILESYNC_INSTALL_PREFIX`**: for `filesync update` from a git checkout when installing an update, overrides the inferred `PREFIX` passed to `make install` when autodetection is wrong.
- **`FILESYNC_VERBOSE`**: when set to a **non-empty** value, enables extra informational messages on stderr (where supported).
- **`FILESYNC_DEBUG`**: when set to a **non-empty** value, enables a short debug line on stderr when a command fails under `set -e` (ERR trap / errtrace).
- **`FILESYNC_NO_PROGRESS`**: when set to `1`, disables TTY progress output (overrides `progress_display`).
- **`NO_COLOR`**: when set to a **non-empty** value, disables ANSI color sequences in terminal output.

## Dependencies

`jq` is required. **`git`** must be on `PATH` for: `check`, `sync`, `list-files`, `list-repos`, `add-file`, `add-master`, `add-clone`, `push`, `detach-file`, `attach-file`, `detach-repo`, `attach-repo`, `remove-file`, `remove-repo`, and `edit-repo` (the shared runtime checks for `git` even when a given command does not invoke it). Other commands (`init`, `update`, `enable`, `disable`, `progress`, `path-mode`, `add-repo`) only require `jq` (and `curl` or `wget` for `update` when fetching release metadata or assets).
