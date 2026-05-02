# filesync

**Stop hand-copying the same file between folders and repos.** filesync is a small Bash CLI that keeps the paths you care about in sync wherever you work—main app, side project, another checkout, all of it. Your project stores its wiring under `.filesync/`; install the tool once on your machine and run it from any folder inside that project.

## Requirements

- `bash`, `jq`, `git`, and `flock` (on Linux, `flock` is in **util-linux**, usually already installed)
- `curl` or `wget` (for **`filesync update`** only)

**ShellCheck** is not required to run filesync; it is only for contributors who run [scripts/lint.sh](scripts/lint.sh) or CI.

## Install (system-wide)

From a clone of this repository:

```bash
sudo make install
```

`make install` runs [scripts/check-install-deps.sh](scripts/check-install-deps.sh) first and **fails with install hints** if `bash`, `jq`, `git`, or `flock` is missing. That check is **skipped** when `DESTDIR` is set (packaging / staged trees). To bypass it: `make install SKIP_INSTALL_DEPS_CHECK=1`.

Default prefix is `/usr/local` (`filesync` → `/usr/local/bin/filesync`, package files under `/usr/local/lib/filesync/`). The binary on `PATH` is a **symlink** to `PREFIX/lib/filesync/bin/filesync`; libraries and commands live under `PREFIX/lib/filesync/`. The dispatcher resolves that symlink using **`readlink -f`** (GNU coreutils), **`realpath`**, or a manual symlink chase so `ROOT` points at `PREFIX/lib/filesync`; without a usable `readlink`/`realpath`, a symlink-only install layout may fail to find `lib/`. Override with `PREFIX`:

```bash
sudo make install PREFIX=/usr
```

Staging for packages:

```bash
make install DESTDIR=/tmp/stage PREFIX=/usr
```

Remove a non-packaged install (does not remove `.deb` packages; use `apt`/`dpkg` for those):

```bash
sudo make uninstall
sudo make uninstall PREFIX=/usr
```

The installed `filesync --version` string comes from `share/VERSION` in the install tree. For **git tags / `.deb` builds**, [scripts/build-deb.sh](scripts/build-deb.sh) overwrites that file in the package so it matches the `VERSION` environment variable (the release workflow sets this from the tag). Bump [share/VERSION](share/VERSION) in the repository when you cut a release so tarballs and `make install` from a source tree stay aligned. Maintainers can use [scripts/version-push.sh](scripts/version-push.sh) to bump that file, commit, tag `v…`, and push (see **Developing** below).

### Releases

GitHub Releases publish a **source tarball** (`make install` from the extracted tree) and a **`.deb`** (`Depends: bash, jq, git`) for Debian/Ubuntu. Download the `.deb` and run `sudo apt install ./filesync_*_all.deb` (or `sudo dpkg -i …`).

### Updating filesync

- **`filesync update`** — compares your install to the [latest GitHub release](https://github.com/AragusNZ/tool-filesync/releases/latest). If a newer version exists and the install can be upgraded automatically (git checkout of filesync, or a matching release **`.deb`**), prompts to apply it (**`git pull`** + **`make install`**, or **`dpkg -i`** the **`.deb`**; **`sudo`** is used when on `PATH`). Use **`-y`** or **`--yes`** to skip the prompt. If you are already up to date, it says so; if an update exists but cannot be applied from this layout, it points you to the release page.

## Usage

Create a new project (writes `./.filesync/` in the current directory — that folder’s parent is the **project root** for this tree). From an interactive terminal, **`filesync init`** can also prompt to add a matching entry to the **global** `repos.json` (name, checkout **path**, URL, branch). The path is relative to **`repo_path_root`** (usually home) or absolute; Enter accepts the default from the project directory / git top. Defaults for name, URL, and branch come from **git** when applicable. Use **`filesync init --no-repo`** (or run without a TTY) to skip that step and use **`filesync new repo`** later (same path prompt).

```bash
cd /path/to/your/project
filesync init
```

From any directory under a project that contains `.filesync/` (discovery walks up toward `/`, like `git`):

```bash
filesync check
filesync check --repo=api --file=src/types.ts
filesync sync --file=lib/config.py --dry-run
filesync sync --repo-file=internal/legacy.toml
filesync list files --all-files=schema.graphql
filesync list files --repo=api
filesync list files
```

**Development without install:** run `./bin/filesync` from this tree (or `bash /path/to/filesync/bin/filesync …`).

Commands: `init`, `config` (including `config set progress …`), `migrate`, `handle-missing`, `sync` (`s`; optional `--move` / `--mv`), `check` (`c`), `doctor` (`inspect` default; `doctor clean` for ghost marker cleanup), `info` (`i`; `info --help` shows file + repo forms), `retarget clone` / `retarget master` (`-c` / `-m`; **`retarget -h`** for compound help), `list repos` / `list files` / `list collections` (`l -r`, `l` / `l -f`, `l -col`), `add file` / `add master` / `add clone` (`a`, `a -m`, `a -c`), `push`, `detach file` / `detach files-in-repo` (`d`, `d -fir`), `attach file` / `attach files-in-repo` (`da`, `da -fir`), `remove file` / `remove repo` / `remove collection` (`rm`, `rm -r`, `rm -col`), `new repo` / `new collection` (`n -r`, `n -col`), `edit repo` / `edit collection` (`e -r`, `e -col`), `update`. Run **`filesync`** with no arguments for the summary.

**`check`**, **`sync`**, **`list repos`**, and **`list files`** accept optional **`--repo=name`**. **`check`**, **`sync`**, and **`list files`** accept path fragments: **`--file=`** (`local_path` only), **`--repo-file=`** (`repo_file_path` only), **`--all-files=`** (either path). Repeat a flag to OR within that dimension; nonempty dimensions are ANDed. **`check`** also accepts **`--status=a,b,...`** (same token rules as `sync`/`list files`). Combine filters to narrow scope.

**`info`** (alias **`i`**) can target a **file** or a **repo**: optional **`file`** / **`-f`** then **`local-path`** (or **`info <local-path>`** / **`i <local-path>`** with no keyword) refreshes every mapping that shares the same master across known projects (**`check`** with **`--file=`** per affected path), prints a summary on stderr (**`Role: master`** or **`Role: clone`**, related rows per project), then optionally prompts (or **`--fix-marker`**) to add or remove **`kind=master`** on the canonical master file when it does not match whether clones exist. **`info repo <name>`** (or **`info -r`**) prints global catalog fields for that repo, verifies the checkout directory exists (same rules as **`doctor inspect`**), and summarizes **`files.json`** rows in the current project (by **`sync_status`**; run **`check --repo=`** to refresh). **`filesync info --help`** (or **`i --help`**) prints help for both **`info file`** and **`info repo`**; per-subcommand text is in **`filesync info file --help`** and **`filesync info repo --help`**. See **`man filesync`**.

**`add file`**, **`add master`**, and **`add clone`** support **`--also=`** with comma-separated **repo names** and/or **collection names** from the **global** `collections.json`. Define groups with **`new collection`** (`n -col`), **`edit collection`** (`e -col`), **`remove collection`** (`rm -col`); list them with **`list collections`** (`l -col`). Each resolved repo must exist in the **global** `repos.json` with `path` resolved under **`repo_path_root`** (see **`filesync config show`**); the resolved checkout directory must be an initialized project (contains `.filesync/files.json`). **`--also`** skips targets whose checkout equals the current project root and respects per-repo **`mirror_in_enabled`**. Collection and repo names share one namespace. Empty collections cannot be used with **`--also=`**. The first argument to **`add clone`** may be a repo or collection (collections expand like **`--also=`**; primary and **`--also=`** lists are merged and deduplicated, then the same skip rules apply). The first argument to **`add file`** and **`add master`** must resolve to **exactly one** repo (a plain repo name or a collection that contains a single repo); if you need multiple targets, specify the source/master repo explicitly and pass a multi-member collection with **`--also=`**. For **`add file`**, the path in the repo must already have a **`kind=master`** marker unless you pass **`--mark-master`**, which prepends one when the repo file has no filesync marker yet.

**`filesync push`** copies local clone content to the linked master paths (reverse of default **`sync`**). Use **`--all`** to include every mapping whose status is **`local_newer`**, combined with any explicit paths you list. **`push --to-clones <path>`** propagates an edited canonical master to every tracked clone row across the project union (runs **`sync`** with **`--file=`** and **`--force`** per project). See [docs/configuration.md](docs/configuration.md) and **`man filesync`** for details.

**`filesync remove file`** (also **`rm`**, **`rm -f`**) accepts **`--all-missing`** to remove every mapping whose cached **`sync_status`** is **`error_missing_master`**, combined with any explicit paths; see [docs/configuration.md](docs/configuration.md#removing-mappings) and **`man filesync`**.

**`handle-missing`** runs from a project directory and repairs one row by **`local_path`**: **`--unmap`**, **`--delete-local-and-unmap`**, or **`--recreate-from-master`** (exactly one). See **`filesync handle-missing -h`**.

**Detach** vs **remove**: **`detach file`** / **`detach files-in-repo`** keep the row but mark it **`detached`**; **`remove file`** drops the mapping and strips clone/detached markers on disk; **`remove repo`** removes a global repo entry. If any `files.json` row still references that repo, you must pass **`--force`** (which removes those mappings like **`remove file`**), then confirm unless you pass **`-y`** / **`--yes`**. See [docs/configuration.md](docs/configuration.md#removing-mappings).

When a repo has **`check_sync_enabled: false`** in the global store, use **`filesync edit repo <name> --disable`** (or **`--check-sync=false`**); **`check`** and **`sync`** skip every `files.json` row that references that repo. If every selected row is skipped for that reason, the command exits **0** with a short hint.

## Markers

Each tracked text file contains one line with **`filesync`**, **`kind=master`** (in the upstream repo) or **`kind=clone`** plus **`path=`** and **`repo=`** (local copy). After **`detach file`**, **`kind=detached`**. The comment wrapper matches the file type (`#`, `//`, `<!-- … -->`, `/* … */`, `--`, etc.); optional per-row **`marker_style`** in `files.json` overrides inference. Plain **`.json`** cannot carry comments—see [docs/configuration.md](docs/configuration.md).

**`check`** / **`sync`** / **`list files`** status filter **`--status=a,b,...`** (see [docs/configuration.md](docs/configuration.md)): same tokens for all three; **`all`** is every status except **`detached`** unless **`--include-detached`** or **`detached`** is listed; **`error`** matches any **`error_*`**; **`unset`** is empty status. In `check`, status matching uses the cached row status to select which rows to re-check. **`sync`** default (no **`--status`**) includes **`unset`**, **`sync_required`**, and **`error_missing_local`** (so missing local files are recreated from master); add **`--include-detached`** to allow **`detached`** there too. **`sync`** also supports **`-c`** / **`--check`** (run `check` first with matching `--repo`, `--file`, and `--status` filters), **`--dry-run`**, **`-f`** / **`--force`** (overwrite locals that lack the clone marker; and when no **`--status`** is given, also selects **`local_newer`** and **`conflict`** so master replaces local), **`--showall`** (print per-file lines for content-already-matched files and for gray **`synced`** status skips under the default filter; default hides those).

If the first argument starts with `-` but is not a known subcommand, it is treated as a **`sync`** option (same as calling `sync` first).

Run `filesync` with no arguments to print a short usage summary (same idea as **`filesync help`**). **`filesync --version`** / **`filesync -v`** print the version; **`man filesync`** is available after install.

## Layout (source / install tree)

| Path | Role |
|------|------|
| `bin/filesync` | Dispatcher |
| `commands/*.sh` | Subcommand implementations (e.g. `list.sh` takes first argv `repos` \| `files` \| `collections`) |
| `lib/*.sh` | Resolve project, merge config, assemble state JSON, paths, status |
| `share/defaults/preferences.default.json` | Defaults merged into system `preferences.json` |
| `share/VERSION` | Single-line version for `filesync --version` |
| `man/filesync.1` | Manual page (installed under `PREFIX/share/man/man1/`) |

## User data: system store + project `.filesync/`

**System metadata** (always **`~/.filesync-root`**, or **`FILESYNC_HOME`** when that environment variable is set — intended for tests and automation; do not point different projects at different catalogs): `repos.json`, `collections.json`, `system.json` (version and other metadata), and `preferences.json` (**`progress_display`**, etc.). Each repo row includes required boolean **`merge_using_git`** (set when adding a repo from a git probe at that checkout, or backfilled by **`migrate`**). Relative repo `path` values in `repos.json` resolve under your home directory (or **`FILESYNC_REPO_PATH_ANCHOR`** when set); absolute paths are used as-is. **`filesync config show`** prints the effective repo path anchor.

**`filesync doctor`** (same as **`filesync doctor inspect`**) checks global **`repos.json`** (duplicate names, missing checkout directories) and, when run from inside a filesync project, validates **`files.json`** (duplicate **`local_path`**, unknown **`repo_id`**), compares **`kind=clone`** marker tokens to rows, flags orphan clone markers, and scans for **`kind=master`** files with no tracked clones (see **`filesync info file`**). Output uses sections plus a summary line. Use **`filesync doctor clean`** to remove ghost non-master markers on disk.

**Per project** (discovered like git: walk up for **`.filesync/`**): **`files.json`** only. If you still have old per-project `repos.json` / `collections.json` / `config.json`, run **`filesync migrate`** once to import them into the global store (legacy repos are merged by **`name`** with the global catalog; an existing name keeps the global row even when path/URL/branch differ).

**`sync` and git:** If a repo’s **`merge_using_git`** is **`true`** and the project is a git work tree with **no dirty paths except possibly** **`.filesync/files.json`** (for example after **`check`** or **`sync -c`** refreshes it), **`sync`** applies updates on a short-lived branch and merges back so you can resolve conflicts with normal git tools. Otherwise it writes files directly. **`sync --no-commit`** forces that direct-write behavior for the run (ignoring **`merge_using_git`** for batching and sync commits), so a dirty tree does not block **`sync`** the way it does on the merge path. See [docs/configuration.md](docs/configuration.md) (`merge_using_git` and `sync`).

Basenames are defined in `lib/data-names.sh` if you need to change them in a fork.

Overrides: **`FILESYNC_PROJECT_ROOT`** or **`FILESYNC_DIR`** for the project; **`FILESYNC_HOME`** only for an alternate system metadata directory in automation (see [docs/configuration.md](docs/configuration.md)).

## Docs

- [Configuration and environment](docs/configuration.md)

## Developing

- **Tests**: `tests/lib/*.sh` exercise `lib/*.sh` (no install); `tests/commands/*.sh` exercise the staged CLI. Run **`bash tests/run-lib-tests.sh --list /path/to/repo`** or **`bash tests/run-command-tests.sh --list /path/to/repo`** to see files; **`--filter SUBSTR`** limits runs (substring match on each script basename).

- **Lint**: [scripts/lint.sh](scripts/lint.sh) runs **ShellCheck** on the same paths as CI (`bin/filesync`, `commands/*.sh`, `lib/*.sh`, selected `scripts/` and `tests/`). Options such as **`external-sources`** and **`source-path`** come from [`.shellcheckrc`](.shellcheckrc) at the repo root. Install **`shellcheck`** (e.g. `apt install shellcheck`). From the repo root: **`bash scripts/lint.sh`** (ShellCheck only). Add **`--tests`** to run **`scripts/ci-test.sh`** next; **`--deb`** to build a `.deb` and run **`lintian --fail-on warning`** (needs **`dpkg-dev`** and **`lintian`**; **`VERSION`** defaults to **`0.0.0-ci`**). **`--all`** runs ShellCheck, tests, and deb+lintian — matching the GitHub Actions job.

- **Version bump and release push**: [scripts/version-push.sh](scripts/version-push.sh) reads the first line of **`share/VERSION`**, increments the **patch** (third) number by default, writes the file, **`git commit`s**, creates an annotated tag **`vX.Y.Z`**, then runs **`git push`** (current branch) and **`git push origin vX.Y.Z`**. Use **`--minor`** or **`--major`** to bump the second or first number instead (and reset lower segments to **0**). Requires a **clean** working tree, a **branch** checkout (not detached `HEAD`), and that the new tag does not already exist. Run it **only when you intend to publish a new version**, not on every commit.

CI runs the same steps as **`bash scripts/lint.sh --all`** (ShellCheck path list in [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

## License

See [LICENSE](LICENSE).

## Embedding

You can keep this tree as a nested git repo, submodule, or subtree; for automation, install via `make install` or the release `.deb` so `filesync` is on `PATH`.
