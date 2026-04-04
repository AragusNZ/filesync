# filesync configuration

State is split between a **system metadata directory** (repos, collections, preferences) and each **project** `.filesync/` directory (**`files.json`** only for new installs). Basenames are centralized in `lib/data-names.sh`.

## System metadata directory

The catalog is **machine-wide**: **`~/.filesync-root`** (distinct from **`<project>/.filesync/`**). Resolution:

- If **`FILESYNC_HOME`** is set to an absolute path, that directory is used (intended for **tests and CI**). Do **not** set **`FILESYNC_HOME`** in per-project **`.env`** files or you will split the catalog across projects unintentionally.
- Otherwise **`~/.filesync-root`**.

There is no config-file pointer for the system store path; **`filesync config set system-home`** was removed.

If you have an old copy of the global store at **`~/.filesync`** (not the project’s **`.filesync/`** folder), move it yourself once, e.g. **`mv ~/.filesync ~/.filesync-root`**, when **`~/.filesync-root`** does not already exist.

Files in that directory:

- **`system.json`** — metadata (e.g. **`version`**).
- **`repos.json`** — array of repo objects: stable **`id`** (UUID), **`name`**, **`url`**, **`path`**, **`branch`**, required boolean **`merge_using_git`**, optional **`check_sync_enabled`** and **`mirror_in_enabled`** (both default true if omitted). New rows from **`init`** / **`new repo`** set **`merge_using_git`** from a git probe at the registered checkout directory; **`migrate`** backfills the field on older catalogs. Each **`name`** must be unique; duplicate names make resolution ambiguous and are rejected when loading project state. Each repo’s **`path`** is resolved with `filesync_resolve_repo_checkout_dir`: **relative** paths are under your **home directory** (or **`FILESYNC_REPO_PATH_ANCHOR`** when set); absolute **`path`** values are used as-is.
- **`collections.json`** — array of `{ "name", "repos": [ … ] }` for **`--also=`** expansion.
- **`preferences.json`** — merged over `share/defaults/preferences.default.json`; **`progress_display`** is **`percent`**, **`bar`**, or **`hidden`**. Set it with **`filesync config set progress …`**; inspect the effective value with **`filesync config show`**.

**`filesync config show`** prints the effective system home, repo path anchor, and paths to global JSON files. **`filesync config doctor`** summarizes **`FILESYNC_HOME`** (if set) and warns if **`repos.json`** contains duplicate **`name`** values.

## Project `.filesync/`

### `files.json`

JSON **array** of file row objects (paths, **`repo_id`**, `sync_status`, marker-related fields, mtimes, **`last_check_at`** per row, etc.). **`repo_id`** ties each row to a global repo row; the current repo **name** is not stored here (it comes from global **`repos.json`** when commands assemble state). Run **`filesync migrate`** once to upgrade older trees: it backfills **`repo_id`**, strips any persisted **`repo_name`**, and fails if a row cannot be resolved.

Optional **`marker_style`** per row overrides comment wrapping for that path when the tool must emit a marker line without an existing comment wrapper on the line (rare). Allowed values: **`line_slash`** (`//`), **`line_hash`** (`#`), **`line_dash`** (`--`), **`block_c`** (`/* … */` on one line), **`html`** (`<!-- … -->`). If omitted, style is inferred from the file extension or basename (e.g. `Dockerfile` → hash, `.vue` / `.html` → html, `.css` → block, `.sql` → dash; unknown extension defaults to **`line_hash`**).

### Legacy per-project files

If **`repos.json`**, **`collections.json`**, or **`config.json`** still exist under `.filesync/`, run **`filesync migrate`** once to import them into the global store (backups under **`.filesync/legacy-backup/`**). Legacy **`repos.json`** rows are merged by **`name`**: if that name already exists in the global catalog, the global row is left unchanged (per-project path/URL/branch are not applied), with a stderr notice when they differ; only new names are appended. **`migrate`** also assigns missing **`id`** values on global repos, **`repo_id`** on **`files.json`** rows in every known project, and **`merge_using_git`** on global repo rows when missing. Afterwards the project should keep **`files.json`** only.

### Sync markers (text files)

Each synced copy carries a single-line **marker** containing the substring **`filesync`** and a **`kind=`** field:

- **`kind=master`** — file in the upstream repo (source of truth).
- **`kind=clone`** — coupled local copy; includes **`path=…`** (repo-relative path), **`repo=…`** (repo name), and usually **`repo_id=…`** (stable id matching **`repos.json`**).
- **`kind=detached`** — local file after **`detach file`**; optional **`path=`** / **`repo=`** / **`repo_id=`** for context.

The tool rewrites the first marker line when syncing or changing coupling; the **comment style** around that payload matches the source file (or `marker_style` / extension rules above). Standard **`.json`** does not allow comments; use a commented dialect (e.g. JSONC) and map extension/basename, or avoid markers inside strict JSON.

### Writes

Commands such as **`check`** and **`info`** (via subprocess **`check`**) update row-level fields in **`.filesync/files.json`** (including per-row **`last_check_at`**). **`info`** may also rewrite the canonical master file’s marker when you confirm the prompt or pass **`--fix-marker`**. Global **`repos.json`**, **`collections.json`**, and **`preferences.json`** are usually written by **`jq`** to a temp file, then replaced with **`mv`**. **`config set`**, **`new repo`**, **`edit repo`**, **`migrate`**, **`remove repo`**, and **`init`** (when appending a global repo) also take **`flock`** on **`.lock`** in the metadata directory so concurrent writers do not read partial state; some collection-only paths use temp + **`mv`** without that global lock.

## Project discovery

1. If `FILESYNC_PROJECT_ROOT` is set: that directory is the project root; `.filesync` defaults to `$PROJECT_ROOT/.filesync` unless `FILESYNC_DIR` is set.
2. If only `FILESYNC_DIR` is set: that path is the `.filesync` directory; project root is its parent.
3. Otherwise: if **`cwd`** lies inside a registered repo checkout (from **global** **`repos.json`**) that contains **`.filesync/files.json`** at the checkout root, that checkout directory is the **project root**.
4. Otherwise: from **`cwd`**, walk up until a directory **`D`** exists where **`D/.filesync`** is present; **`D` is the project root**.

### `filesync init`

**`filesync init`** (optional path; default: current directory; optional **`--no-repo`**) creates **`<dir>/.filesync/files.json`** as an empty array and ensures the **system store** exists (default under **`~/.filesync-root`** or **`FILESYNC_HOME`**). It does **not** walk parents. If **`files.json`** already exists, **`init`** exits with an error.

When **stdin is a terminal** and **`--no-repo`** is not passed, **`init`** prompts to append a repo row to **global** **`repos.json`** (name, URL, branch, new stable **`id`**); the checkout **`path`** is stored relative to your home directory when possible (git work tree top when inside git, otherwise the project root). If the project is inside a **git** work tree, defaults for name, URL, and branch come from the work tree root, **`origin`** (or the first remote), and the current branch. An empty repo name at the prompt skips the global row. Non-interactive runs skip this step (with a short notice unless **`--no-repo`** was passed).

### Enable / disable (per repo)

Use **`filesync edit repo <name> --enable`** or **`--disable`** to set both **`check_sync_enabled`** and **`mirror_in_enabled`** true or false in **global** **`repos.json`**, or set them independently with **`--check-sync=true|false`** and **`--mirror-in=true|false`**. Use **`--merge-using-git=true|false`** to control whether **`sync`** applies tracked-file updates via a short-lived git branch and merge in the project (requires a git work tree with no dirty paths except possibly **`.filesync/files.json`**). Rows referencing a repo with **`check_sync_enabled: false`** are skipped by **`check`** and **`sync`**.

### `merge_using_git` and `sync`

Each global repo row’s **`merge_using_git`** only affects how **`sync`** writes **tracked file content** into the **current project** when that project’s root is a **git work tree**:

- **`true`**: before the first content-changing sync for that repo in a run, the project must have **no dirty paths** except possibly this project’s **`files.json`** (under your **`FILESYNC_DIR`**, usually **`.filesync/files.json`**)—for example after **`check`** or the embedded **`check`** in **`sync -c`**. Any other change still blocks the git batch. **`sync`** creates a branch `filesync/sync-…`, writes updated clones there, commits, checks out your previous branch, and **`git merge`**’s the sync branch (then deletes it on success). After a successful batch it **commits** the refreshed **`files.json`** as well—**`git commit --amend`** on the merge commit when **`git merge`** produced one, otherwise a small follow-up commit—so the project work tree is not left dirty. Conflicting paths may be marked **`conflict`** in **`files.json`**; up to **three** merge attempts can drop conflicting paths and retry the rest. Use normal git conflict resolution if a merge stops mid-way.
- **`false`**: **`sync`** overwrites local paths directly (same as older behavior).

If the project is **not** a git repository, **`merge_using_git`** is ignored for that run (direct writes). The add-time probe sets **`merge_using_git`** from whether the **registered checkout directory** (that row’s **`path`**) is a git work tree; **`edit repo --merge-using-git=`** overrides. Upgrading old **`repos.json`** without the field: run **`filesync migrate`**.

## Assembled state

Internally, project commands build a **temporary** JSON file with **`repos`**, **`files`** (each row from disk plus an assembled **`repo_name`** looked up from **`repo_id`**), merged **preferences**, and **`repo_path_root`** (the effective path anchor, for **`jq`**) for filtering. **`collections`** are **not** embedded; commands that need them read **`FILESYNC_COLLECTIONS_FILE`** separately or use **`jq --slurpfile`**.

## Repo metadata (`edit repo`)

**`filesync edit repo <repo_name>`** (short: **`e -r`**) updates **global** **`repos.json`** only (system store). Pass at least one of **`--rename=`**, **`--path=`**, **`--url=`**, **`--branch=`**, **`--check-sync=true|false`**, **`--mirror-in=true|false`**, **`--merge-using-git=true|false`**, **`--enable`**, or **`--disable`** (the **`=`** options use a single argument, e.g. **`--rename=myrepo`**). It does **not** modify project **`files.json`** or local sync markers; the new name must not match any **collection** name in **global** **`collections.json`**.

## Adding mappings (`add file`, `add master`, `add clone`)

**`add file`** (**`a`**, **`a -f`**) tracks paths from a repo checkout into the project. The file under the repo must already contain a **`kind=master`** marker; **`kind=clone`** (or another non-master marker) is rejected. If the repo file has **no** filesync marker yet, pass **`--mark-master`** so the tool prepends a master marker (comment style follows the path).

**`add master`** promotes local files into the master repo checkout and adds mappings; omit **`:path_in_repo`** when it matches **`local_path`**. See **`man filesync`** for arguments and **`--also`**.

**`add clone`** creates a **`kind=clone`** copy and row in a **sibling** initialized project from a **`kind=master`** file that lives under the **current** project. If that source file has no filesync marker, a **`kind=master`** marker is prepended automatically; other non-master markers are rejected. This differs from **`add file`**, where an unmarked repo file requires **`--mark-master`** explicitly.

## Removing mappings

- **`detach file`** / **`detach files-in-repo`**: the row stays in **`files.json`** with **`sync_status: detached`**; the local file’s marker becomes **`kind=detached`**. Use when you want to pause syncing but keep the mapping.
- **`remove file`** (also **`rm`**, **`rm -f`**): removes the row from **`files.json`** and strips **`kind=clone`** or **`kind=detached`** markers from the local file; **`kind=master`** in the repo checkout is unchanged. Pass **`--all-missing`** to also remove every mapping whose cached **`sync_status`** is **`error_missing_master`**, unioned with any explicit paths (similar to how **`push --all`** adds all **`local_newer`** rows). If only **`--all-missing`** is given and no rows match, the command exits **0** after a short message. Full syntax is in **`man filesync`**.
- **`remove repo`**: removes a repo from **global** **`repos.json`** after removing **all** mappings for that repo across **every known project** (registered checkouts with **`.filesync/files.json`**, plus the current project). See the next section.

## Removing a repo (`remove repo`)

**`filesync remove repo`** (also **`rm -r`**) drops an entry from **global** **`repos.json`**. The repo name is removed from every **global** **`collections.json`** entry, and collections that become empty are removed. Discovery is the same union as **`sync`**: registered checkouts that have **`.filesync/files.json`**, plus the current project root. If **any** **`files.json`** still references that repo, the command fails until you pass **`--force`**; then it asks for confirmation unless **`-y`** / **`--yes`**. On success, each mapping is removed the same way as **`remove file`**, then the global repo row is removed. See **`man filesync`** for details.

## `check` / `sync` / `list repos` / `list files` / `list collections` filters

- **`--repo=name`**: for **`check`**, **`sync`**, and **`list files`**, only rows where `repo_name` equals this name. For **`list repos`**, show only that repo’s entry.
- **`--file=fragment`**: for **`check`**, **`sync`**, and **`list files`**, only rows where `local_path` **or** `repo_file_path` contains the fragment (substring / “like” match). Whitespace is trimmed from the fragment; an empty value matches all rows. Not valid for **`list repos`** or **`list collections`**. Do not combine **`--file=`** with **`--exact-local=`** on **`check`** or **`sync`**.
- **`--exact-local=path`**: for **`check`** and **`sync`**; may be repeated; each value must equal a row’s project-relative **`local_path`** exactly (safe for paths where a substring match would be ambiguous). Used internally by **`info`** when refreshing sibling mappings, and by **`push --to-clones`** when invoking **`sync`** per project.
- **`list collections`** accepts no options (no **`--repo`**, **`--file`**, **`--status`**, or **`--include-detached`**).

**`attach file`** (and **`attach files-in-repo`**, which runs it for every row for a repo): re-couples rows with `sync_status: detached` by rewriting the local file from master (clone marker), clearing `sync_status`, then running **`check`** for that repo and path so status is recomputed. **`detach files-in-repo`** runs **`detach file`** for every mapping whose **`repo_id`** matches the named global repo.

## Inspecting (`info`)

**File (same master):** **`filesync info [file | -f] <local-path>`** or **`filesync i <local-path>`** with no keyword. From the current project it resolves the path to either a tracked clone (**`files.json`** row) or the canonical master file under a registered repo checkout (internally **master-at-checkout**; the summary prints **`Role: clone`** or **`Role: master`**). It gathers every **`files.json`** row across the same **project union** as **`remove repo`** that shares that master (same **`repo_id`** and **`repo_file_path**), runs **`check --exact-local=`** for the affected rows in each project, prints a summary on stderr (master key, each related row and consumer **project** root), then optionally prompts (if stdin is a TTY) or accepts **`--fix-marker`** to align **`kind=master`** on the canonical master file with whether any clones are tracked. Exit status follows **`check`** when **`check`** reports blocking issues.

**Repo:** **`filesync info repo <name>`** or **`filesync info -r <name>`** (also **`i repo`** / **`i -r`**) prints global catalog fields for that repo, checks that the configured checkout path exists on disk (same resolution as **`config doctor`**), and summarizes **`files.json`** rows in the **current** project for that repo (cached **`sync_status`**; run **`check --repo=`** to refresh). Exits unsuccessfully if the name is missing from global **`repos.json`**.

**Help:** **`filesync info --help`** or **`i --help`** (no other arguments) prints combined usage for both forms above. **`filesync info file --help`** and **`filesync info repo --help`** print each form alone. See **`man filesync`**.

## Push (`push`)

**`filesync push`** writes local clone content to the master path in the linked repo (the inverse of copying from master during **`sync`**). Use **`filesync push [--all] [<local_path> …]`**: **`--all`** adds every mapping whose **`sync_status`** is **`local_newer`**, unioned with any paths you list. If **`--all`** is given with no paths and there are no **`local_newer`** rows, the command exits successfully after a short message.

**`filesync push --to-clones <path>`** resolves **`path`** like **`info file`** (tracked clone or master under a repo checkout), then runs **`sync -c --repo=… --exact-local=… -f --status=all`** in each project that has a related row so the edited master overwrites every clone (multi-project union). **`sync -c`** refreshes **`sync_status`** first; **`--status=all`** ensures each selected row is still diffed and updated if the working-tree master and local clone differ. **`--dry-run`** is passed through to **`sync`**. Do not combine **`--to-clones`** with **`--all`** or extra **`local_path`** arguments. Full behavior is in **`man filesync`**.

## Cross-project mirroring (`--also`)

**`add file`**, **`add master`**, and **`add clone`** accept **`--also=`** with comma-separated **repo names** and/or **collection names** (from **global** **`collections.json`**) to mirror mappings into sibling initialized projects.

- After expanding collection names to their **`repos`** lists (order preserved; duplicates removed), every target must be a repo name in **global** **`repos.json`** with **`mirror_in_enabled`** true (default).
- The resolved checkout directory for each target must contain **`.filesync/files.json`** (sibling project). Targets whose resolved directory **equals** the current project root are filtered out.
- For `add master --also` and `add clone --also`, mirrored rows in sibling projects are initialized as **`sync_required`** so each project can run **`check`** / **`sync`** to compute timestamps and verify status in its own context.

## `retarget` (clone vs master)

**`filesync retarget <local_file|old_path> <new_repo_file_path> [--move|--mv]`** updates **`repo_file_path`** after the master file moved in the repo (**`git mv`**, then the new path must exist with **`kind=master`**). The first argument is resolved like **`info file`** (often the clone still at the pre-move **`local_path`**, or the master path in the checkout); **which kind of path you pass changes scope**:

- **Clone** — **`local_file|old_path`** points at a tracked clone in the **current** project. Only **that project's** row is updated. Without **`--move`**, status becomes **`sync_required`** and the file stays at the old **`local_path`**. With **`--move`**, the clone is moved on disk to **`new_repo_file_path`** (project-relative) and **`local_path`** is updated.
- **Master** — **`local_file|old_path`** points at the master file under a **registered checkout**. **Every** mapping for that master is updated (same multi-project union as **`info file`** / **`remove repo`**). Without **`--move`**, rows get **`master_file_moved`** so you can run **`sync --move`** later to align **`local_path`** with **`repo_file_path`**. With **`--move`**, each local clone is moved and **`local_path`** is updated (not allowed if two rows in the same project share that master — destination collision).

If **`files.json`** still points at the old path after **`git mv`**, **`retarget`** may infer the old path from missing master files; if that fails, pass a **clone** path as **`local_file|old_path`**. See **`filesync retarget -h`** and **`man filesync`**.

## `sync` / `list files` status filter (`--status`)

**`list files`**: optional **`--status=a,b,...`** and optional **`--include-detached`** (with **`--status`** only). Omit **`--status`** to list every row (after **`--repo`** / **`--file`** filters).

**`sync`**: by default only rows whose **`sync_status`** is **unset**, **`sync_required`**, **`error_missing_local`**, or **`master_file_moved`** are processed (so missing local files are recreated from master, and retargeted masters can still be pulled to the old **`local_path`** until you run **`sync --move`**); **`detached`** rows are skipped unless **`--include-detached`** is set. Pass **`--status=`** to replace that default with other tokens. **`sync --move`** (or **`--mv`**) relocates locals whose status is **`master_file_moved`** so **`local_path`** matches **`repo_file_path`**, then syncs as usual.

Comma-separated tokens (whitespace around tokens is stripped). A row matches if **any** token matches (OR):

- **`unset`** — empty / missing **`sync_status`**
- **`all`** — every status **except** **`detached`**, unless **`--include-detached`** is set (then **`all`** includes **`detached`** too) or the list also contains the literal token **`detached`**
- **`error`** — any **`sync_status`** whose name starts with **`error_`**
- any other token — exact **`sync_status`** string (e.g. **`synced`**, **`local_newer`**, **`detached`**, **`error_repo_unavailable`**)

Examples: **`--status=all`** (all non-detached); **`--status=all --include-detached`** or **`--status=all,detached`** (include detached); **`--status=error`**; **`--status=sync_required,local_newer,synced`**.

## `sync` behavior and flags

- **`-c`** / **`--check`**: run `filesync check` first with matching `--repo`, `--file`, and `--status` filters before syncing. If that preflight check fails, sync exits without copying.
- **`--include-detached`**: allow **`sync_status: detached`** rows when using the default status filter, or include them when **`--status=`** contains **`all`** (without adding the **`detached`** token).
- **`--dry-run`**: report what would be copied; do not write files or update `files.json`.
- **`--force`**: if the local file exists but lacks the **`filesync kind=clone`** marker, sync anyway (default is to skip those paths). When no **`--status`** filter is given, **`--force`** also selects **`local_newer`** and **`conflict`** rows so master replaces local.

Master files must contain **`filesync kind=master`** or the row is skipped (with a warning), regardless of other flags.

## Environment variables

- **`FILESYNC_HOME`**: absolute path to the system metadata directory (overrides default **`~/.filesync-root`**). Use only for tests, CI, or deliberate machine-local overrides — not per-project **`.env`**.
- **`FILESYNC_REPO_PATH_ANCHOR`**: optional absolute directory used **instead of `$HOME`** when resolving **relative** `path` values in **global** **`repos.json`** (tests and specialized layouts). Not needed for normal use.
- **`FILESYNC_SYSTEM_HOME`**: set by the tool to the resolved metadata directory — **do not** rely on setting it yourself as input.
- **`FILESYNC_PROJECT_ROOT`**: forces the project root (discovery does not walk parents); `.filesync` defaults to `$FILESYNC_PROJECT_ROOT/.filesync` unless `FILESYNC_DIR` is also set.
- **`FILESYNC_DIR`**: forces the `.filesync` directory path; project root becomes its parent.
- **`FILESYNC_INSTALL_PREFIX`**: for `filesync update` from a git checkout when installing an update, overrides the inferred `PREFIX` passed to `make install` when autodetection is wrong.
- **`FILESYNC_VERBOSE`**: when set to a **non-empty** value, enables extra informational messages on stderr (where supported).
- **`FILESYNC_DEBUG`**: when set to a **non-empty** value, enables a short debug line on stderr when a command fails under `set -e` (ERR trap / errtrace).
- **`FILESYNC_NO_PROGRESS`**: when set to `1`, disables TTY progress output (overrides `progress_display`).
- **`NO_COLOR`**: when set to a **non-empty** value, disables ANSI color sequences in terminal output.

## Dependencies

`jq` is required. **`git`** must be on `PATH` for commands that load a project and work with **`files.json`** mappings (or global repo removal that scans those projects): `check`, `sync`, `list files`, `add file`, `add master`, `add clone`, `push`, `detach file`, `attach file`, `detach files-in-repo`, `attach files-in-repo`, `remove file`, `remove repo`, `info`, and `handle-missing`. Commands that only read or edit the global catalog (`list repos`, `list collections`, `config`, `new repo`, `edit repo`, `new collection`, `edit collection`, `remove collection`) do **not** require `git` at startup. `init`, `migrate`, and `new repo` use **`git`** when it is installed (defaults and `merge_using_git` probing) but do not fail the dependency check if **`git`** is missing. **`update`** only requires `jq` (and `curl` or `wget` when fetching release metadata or assets).
