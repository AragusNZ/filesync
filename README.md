# filesync

**Stop hand-copying the same file between folders and repos.** filesync is a small Bash CLI that keeps the paths you care about in sync wherever you work—main app, side project, another checkout, all of it. Your project stores its wiring under `.filesync/`; install the tool once on your machine and run it from any folder inside that project.

## Requirements

- `bash`, `jq`, `git`
- `curl` or `wget` (for **`filesync update`**)

## Install (system-wide)

From a clone of this repository:

```bash
sudo make install
```

Default prefix is `/usr/local` (`filesync` → `/usr/local/bin/filesync`, package files under `/usr/local/lib/filesync/`). The binary on `PATH` is a **symlink** to `PREFIX/lib/filesync/bin/filesync`; libraries and commands live under `PREFIX/lib/filesync/`. Override with `PREFIX`:

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

- **`filesync update`** — compares your install to the [latest GitHub release](https://github.com/AragusNZ/filesync/releases/latest) and prints upgrade steps.
- **`filesync update --apply`** — from a **git clone**, runs `git pull` then **`make install`** (via **`sudo`** when `sudo` is on `PATH`; default `PREFIX` is derived from the install path; override with **`FILESYNC_INSTALL_PREFIX`** if you used a custom prefix). From a **`.deb`** install, downloads the release `.deb` and runs **`dpkg -i`** (via **`sudo`** when available). Use **`-y`** to skip the confirmation prompt.

## Usage

Create a new project (writes `./.filesync/` in the current directory — that folder’s parent is the **project root** for this tree):

```bash
cd /path/to/your/project
filesync init
```

From any directory under a project that contains `.filesync/` (discovery walks up toward `/`, like `git`):

```bash
filesync check
filesync check --repo=api --file=src/types.ts
filesync sync --file=lib/config.py --dry-run
filesync list-files --repo=api
filesync list-files
```

**Development without install:** run `./bin/filesync` from this tree (or `bash /path/to/filesync/bin/filesync …`).

Primary subcommands: `init`, `enable`, `disable`, `progress`, `show-progress`, `hide-progress`, `path-mode`, `sync`, `check`, `list-repos`, `list-files`, `add-file`, `add-master`, `push`, `detach`, `attach`, `remove`, `add-repo`, `edit-repo`, `update`. Shorter aliases (`s`, `c`, `lr`, `lf`, `files`, `af`, `am`, `p`, `dd`, `da`, `ar`, `er`, `en`, `dis`, `pm`, …) are listed in the built-in help — run **`filesync`** with no arguments. Legacy names `repos`, `list`, `add`, `repo`, and `repo-edit` are still accepted.

**`check`**, **`sync`**, **`list-repos`**, and **`list-files`** accept optional **`--repo=name`**. **`check`**, **`sync`**, and **`list-files`** also accept **`--file=fragment`**: substring match on `local_path` or `repo_file_path` (case-sensitive). **`check`** also accepts **`--status=a,b,...`** (same token rules as `sync`/`list-files`) and matches against each row's current cached `sync_status` before re-checking selected rows. Combine filters to narrow scope.

**`add-file`** and **`add-master`** support **`--also=repo1,repo2`** to mirror mappings into sibling projects. Each value is a repo name from the current project's `.filesync/repos.json` whose configured `path` points at another initialized project root (a directory containing its own `.filesync/`).

When file sync is off in **merged** config (`file_sync_enabled` is not boolean `true` — e.g. after **`filesync disable`**, or `enabled: false` normalized from `config.json`), **`check`** and **`sync`** print a message and exit **0** without doing work.

## Markers

Each tracked text file contains one line with **`filesync`**, **`kind=master`** (in the upstream repo) or **`kind=clone`** plus **`path=`** and **`repo=`** (local copy). After **`detach`**, **`kind=detached`**. The comment wrapper matches the file type (`#`, `//`, `<!-- … -->`, `/* … */`, `--`, etc.); optional per-row **`marker_style`** in `files.json` overrides inference. Plain **`.json`** cannot carry comments—see [docs/configuration.md](docs/configuration.md).

**`check`** / **`sync`** / **`list-files`** status filter **`--status=a,b,...`** (see [docs/configuration.md](docs/configuration.md)): same tokens for all three; **`all`** is every status except **`detached`** unless **`--include-detached`** or **`detached`** is listed; **`error`** matches any **`error_*`**; **`unset`** is empty status. In `check`, status matching uses the cached row status to select which rows to re-check. **`sync`** default (no **`--status`**) is **`unset`** + **`sync_required`**; add **`--include-detached`** to allow **`detached`** there too. **`sync`** also supports **`--dry-run`**, **`--force`** (overwrite locals that lack the clone marker), **`--showall`** (print per-file lines for files already in sync; default hides them).

If the first argument starts with `-` but is not a known subcommand, it is treated as a **`sync`** option (same as calling `sync` first).

Run `filesync` with no arguments to print a short usage summary (same idea as **`filesync help`**). **`filesync --version`** / **`filesync -V`** print the version; **`man filesync`** is available after install.

## Layout (source / install tree)

| Path | Role |
|------|------|
| `bin/filesync` | Dispatcher |
| `commands/*.sh` | Subcommand implementations (e.g. `list.sh` handles both `list-repos` and `list-files`) |
| `lib/*.sh` | Resolve project, merge config, assemble state JSON, paths, status |
| `share/defaults/config.default.json` | Shallow-merge defaults for `.filesync/config.json` |
| `share/VERSION` | Single-line version for `filesync --version` |
| `man/filesync.1` | Manual page (installed under `PREFIX/share/man/man1/`) |

## User data: `.filesync/`

| File | Content |
|------|---------|
| `config.json` | JSON object (partial); merged over package defaults |
| `repos.json` | JSON **array** of repo objects (`name`, `url`, `path`, `branch`, …) |
| `files.json` | JSON **array** of file rows |

Basenames are defined in `lib/data-names.sh` if you need to change them in a fork.

Discovery: walk parents from the current working directory until a directory `D` exists where **`D/.filesync`** is present; **`D` is the project root**. Overrides: `FILESYNC_PROJECT_ROOT` or `FILESYNC_DIR` (see [docs/configuration.md](docs/configuration.md)).

## Docs

- [Configuration and environment](docs/configuration.md)

## Developing

- **Tests**: `tests/lib/*.sh` exercise `lib/*.sh` (no install); `tests/commands/*.sh` exercise the staged CLI. Run **`bash tests/run-lib-tests.sh --list /path/to/repo`** or **`bash tests/run-command-tests.sh --list /path/to/repo`** to see files; **`--filter SUBSTR`** limits runs (substring match on each script basename).

- **Lint**: [scripts/lint.sh](scripts/lint.sh) runs **ShellCheck** (`shellcheck -x`) on the same paths as CI (`bin/filesync`, `commands/*.sh`, `lib/*.sh`, selected `scripts/` and `tests/`). Install **`shellcheck`** (e.g. `apt install shellcheck`). From the repo root: **`bash scripts/lint.sh`** (ShellCheck only). Add **`--tests`** to run **`scripts/ci-test.sh`** next; **`--deb`** to build a `.deb` and run **`lintian --fail-on warning`** (needs **`dpkg-dev`** and **`lintian`**; **`VERSION`** defaults to **`0.0.0-ci`**). **`--all`** runs ShellCheck, tests, and deb+lintian — matching the GitHub Actions job.

- **Version bump and release push**: [scripts/version-push.sh](scripts/version-push.sh) reads the first line of **`share/VERSION`**, increments the **patch** (third) number by default, writes the file, **`git commit`s**, creates an annotated tag **`vX.Y.Z`**, then runs **`git push`** (current branch) and **`git push origin vX.Y.Z`**. Use **`--minor`** or **`--major`** to bump the second or first number instead (and reset lower segments to **0**). Requires a **clean** working tree, a **branch** checkout (not detached `HEAD`), and that the new tag does not already exist. Run it **only when you intend to publish a new version**, not on every commit.

CI runs the same steps as **`bash scripts/lint.sh --all`** (ShellCheck path list in [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

## License

See [LICENSE](LICENSE).

## Embedding

You can keep this tree as a nested git repo, submodule, or subtree; for automation, install via `make install` or the release `.deb` so `filesync` is on `PATH`.
