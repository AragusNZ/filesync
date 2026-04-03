# filesync configuration

State is split between a **system metadata directory** (repos, collections, preferences) and each **project** `.filesync/` directory (**`files.json`** only for new installs). Basenames are centralized in `lib/data-names.sh`.

## System metadata directory

Default: **`~/.filesync-root`** (distinct from **`<project>/.filesync/`**). If **`~/.filesync`** exists and **`~/.filesync-root`** does not, the first run may migrate by renaming that directory (see stderr notice). Resolution order:

1. **`FILESYNC_HOME`** (absolute path; intended for tests and automation — avoid setting it in per-project `.env` if you want a normal shared machine catalog).
2. Else the single line in **`$XDG_CONFIG_HOME/filesync/system_home`** (default **`~/.config/filesync/system_home`**), if present and valid (invalid pointer paths are ignored with a warning; the default directory is used).
3. Else **`~/.filesync-root`**.

Files in that directory:

- **`system.json`** — metadata (e.g. **`version`**).
- **`repos.json`** — array of repo objects: stable **`id`** (UUID), **`name`**, **`url`**, **`path`**, **`branch`**, optional **`check_sync_enabled`** and **`mirror_in_enabled`** (both default true if omitted). Each **`name`** must be unique; duplicate names make resolution ambiguous and are rejected when loading project state. Each repo’s **`path`** is resolved with `filesync_resolve_repo_checkout_dir`: **relative** paths are under your **home directory** (or **`FILESYNC_REPO_PATH_ANCHOR`** when set); absolute **`path`** values are used as-is.
- **`collections.json`** — array of `{ "name", "repos": [ … ] }` for **`--also=`** expansion.
- **`preferences.json`** — merged over `share/defaults/preferences.default.json`; **`progress_display`** is **`percent`**, **`bar`**, or **`hidden`**. Set it with **`filesync config set progress …`**; inspect the effective value with **`filesync config show`**.

**`filesync config show`** prints the effective system home, pointer path, repo path anchor, and paths to global JSON files. **`filesync config doctor`** summarizes pointer / **`FILESYNC_HOME`** overrides and warns if **`repos.json`** contains duplicate **`name`** values.

## Project `.filesync/`

### `files.json`

JSON **array** of file row objects (paths, **`repo_id`**, **`repo_name`**, `sync_status`, marker-related fields, mtimes, **`last_check_at`** per row, etc.). **`repo_id`** ties each row to a global repo row; names can change without rewriting ids. Run **`filesync migrate`** to backfill ids on older trees.

Optional **`marker_style`** per row overrides comment wrapping for that path when the tool must emit a marker line without an existing comment wrapper on the line (rare). Allowed values: **`line_slash`** (`//`), **`line_hash`** (`#`), **`line_dash`** (`--`), **`block_c`** (`/* … */` on one line), **`html`** (`<!-- … -->`). If omitted, style is inferred from the file extension or basename (e.g. `Dockerfile` → hash, `.vue` / `.html` → html, `.css` → block, `.sql` → dash; unknown extension defaults to **`line_hash`**).

### Legacy per-project files

If **`repos.json`**, **`collections.json`**, or **`config.json`** still exist under `.filesync/`, run **`filesync migrate`** once to import them into the global store (backups under **`.filesync/legacy-backup/`**). **`migrate`** also assigns missing **`id`** values on global repos and **`repo_id`** on **`files.json`** rows in every known project. Afterwards the project should keep **`files.json`** only.

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

Use **`filesync edit repo <name> --enable`** or **`--disable`** to set both **`check_sync_enabled`** and **`mirror_in_enabled`** true or false in **global** **`repos.json`**, or set them independently with **`--check-sync=true|false`** and **`--mirror-in=true|false`**. Rows referencing a repo with **`check_sync_enabled: false`** are skipped by **`check`** and **`sync`**.

## Assembled state

Internally, project commands build a **temporary** JSON file with **`repos`**, **`files`** (rows normalized with **`repo_id`** / **`repo_name`**), merged **preferences**, and **`repo_path_root`** (the effective path anchor, for **`jq`**) for filtering. **`collections`** are **not** embedded; commands that need them read **`FILESYNC_COLLECTIONS_FILE`** separately or use **`jq --slurpfile`**.

## Repo metadata (`edit repo`)

**`filesync edit repo <repo_name>`** (short: **`e -r`**) updates **global** **`repos.json`** only (system store). Pass at least one of **`--rename=`**, **`--path=`**, **`--url=`**, **`--branch=`**, **`--check-sync=true|false`**, **`--mirror-in=true|false`**, **`--enable`**, or **`--disable`** (the **`=`** options use a single argument, e.g. **`--rename=myrepo`**). It does **not** modify project **`files.json`** or local sync markers; the new name must not match any **collection** name in **global** **`collections.json`**.

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
- **`--file=fragment`**: for **`check`**, **`sync`**, and **`list files`**, only rows where `local_path` **or** `repo_file_path` contains the fragment (substring / “like” match). Whitespace is trimmed from the fragment; an empty value matches all rows. Not valid for **`list repos`** or **`list collections`**. Do not combine **`--file=`** with **`--exact-local=`** on **`check`**.
- **`--exact-local=path`**: **`check`** only; may be repeated; each value must equal a row’s project-relative **`local_path`** exactly (safe for paths where a substring match would be ambiguous). Used internally by **`info`** when refreshing sibling mappings.
- **`list collections`** accepts no options (no **`--repo`**, **`--file`**, **`--status`**, or **`--include-detached`**).

**`attach file`** (and **`attach files-in-repo`**, which runs it for every row for a repo): re-couples rows with `sync_status: detached` by rewriting the local file from master (clone marker), clearing `sync_status`, then running **`check`** for that repo and path so status is recomputed. **`detach files-in-repo`** runs **`detach file`** for every mapping with that **`repo_name`**.

## Inspecting one path (`info`)

**`filesync info`** (short: **`i`**) takes **`[file | -f] <local-path>`** or, equivalently, **`filesync i <local-path>`** with no extra keyword. From the current project it resolves the path to either a tracked clone (**`files.json`** row) or a file under a registered repo checkout (**master-at-checkout**). It gathers every **`files.json`** row across the same **project union** as **`remove repo`** that shares that master (**`repo_file_path`** + **`repo_id`** / legacy **`repo_name`**), runs **`check --exact-local=`** for the affected rows in each project, prints a summary on stderr, then optionally prompts (if stdin is a TTY) or accepts **`--fix-marker`** to align **`kind=master`** on the canonical master file with whether any clones are tracked. Exit status follows **`check`** when **`check`** reports blocking issues. See **`man filesync`** and **`filesync info file --help`**.

## Push (`push`)

**`filesync push`** writes local content to the master path in the linked repo (the inverse of copying from master during **`sync`**). Use **`filesync push [--all] [<local_path> …]`**: **`--all`** adds every mapping whose **`sync_status`** is **`local_newer`**, unioned with any paths you list. If **`--all`** is given with no paths and there are no **`local_newer`** rows, the command exits successfully after a short message. Full behavior is in **`man filesync`**.

## Cross-project mirroring (`--also`)

**`add file`**, **`add master`**, and **`add clone`** accept **`--also=`** with comma-separated **repo names** and/or **collection names** (from **global** **`collections.json`**) to mirror mappings into sibling initialized projects.

- After expanding collection names to their **`repos`** lists (order preserved; duplicates removed), every target must be a repo name in **global** **`repos.json`** with **`mirror_in_enabled`** true (default).
- The resolved checkout directory for each target must contain **`.filesync/files.json`** (sibling project). Targets whose resolved directory **equals** the current project root are filtered out.
- For `add master --also` and `add clone --also`, mirrored rows in sibling projects are initialized as **`sync_required`** so each project can run **`check`** / **`sync`** to compute timestamps and verify status in its own context.

## `sync` / `list files` status filter (`--status`)

**`list files`**: optional **`--status=a,b,...`** and optional **`--include-detached`** (with **`--status`** only). Omit **`--status`** to list every row (after **`--repo`** / **`--file`** filters).

**`sync`**: by default only rows whose **`sync_status`** is **unset**, **`sync_required`**, or **`error_missing_local`** are processed (so missing local files are recreated from master); **`detached`** rows are skipped unless **`--include-detached`** is set. Pass **`--status=`** to replace that default with other tokens.

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

- **`FILESYNC_HOME`**: absolute path to the system metadata directory (overrides pointer and default **`~/.filesync-root`**). Prefer the pointer file (**`filesync config set system-home`**) for a relocatable user default; reserve **`FILESYNC_HOME`** for CI and automation.
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

`jq` is required. **`git`** must be on `PATH` for: `check`, `sync`, `list files`, `list repos`, `add file`, `add master`, `add clone`, `push`, `detach file`, `attach file`, `detach files-in-repo`, `attach files-in-repo`, `remove file`, `remove repo`, and `info` (the shared runtime checks for `git` even when a given command does not invoke it). Other commands (`init`, `update`, `config`, `migrate`, `handle-missing`, `new repo`, `edit repo`, `new collection`, `remove collection`, `edit collection`, `list collections`) only require `jq` (and `curl` or `wget` for `update` when fetching release metadata or assets).
