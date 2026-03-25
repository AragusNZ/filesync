# filesync

Bash tooling to map and sync files across multiple git checkouts (e.g. a monorepo plus sibling service repos). State lives in the **consuming project** under `.filesync/`; install the CLI once on the system and run it from any directory inside that project.

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

The installed `filesync --version` string comes from `share/VERSION` in the install tree. For **git tags / `.deb` builds**, [scripts/build-deb.sh](scripts/build-deb.sh) overwrites that file in the package so it matches the `VERSION` environment variable (the release workflow sets this from the tag). Bump [share/VERSION](share/VERSION) in the repository when you cut a release so tarballs and `make install` from a source tree stay aligned.

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

Primary subcommands: `init`, `enable`, `disable`, `sync`, `check`, `list-repos`, `list-files`, `add-file`, `add-master`, `push`, `detach`, `attach`, `remove`, `add-repo`, `edit-repo`, `update`. Shorter aliases (`s`, `c`, `lr`, `lf`, `files`, `af`, `am`, `p`, `dd`, `da`, `ar`, `er`, `en`, `dis`, …) are listed in the built-in help — run **`filesync`** with no arguments. Legacy names `repos`, `list`, `add`, `repo`, and `repo-edit` are still accepted.

**`check`**, **`sync`**, **`list-repos`**, and **`list-files`** accept optional **`--repo=name`**. **`check`**, **`sync`**, and **`list-files`** also accept **`--file=fragment`**: substring match on `local_path` or `repo_file_path` (case-sensitive). Combine **`--repo`** and **`--file`** to scope to one repo and matching paths.

When file sync is off in **merged** config (`file_sync_enabled` is not boolean `true` — e.g. after **`filesync disable`**, or `enabled: false` normalized from `config.json`), **`check`** and **`sync`** print a message and exit **0** without doing work.

## Markers

Each tracked text file contains one line with **`filesync:sync`**, **`kind=master`** (in the upstream repo) or **`kind=clone`** plus **`path=`** and **`repo=`** (local copy). After **`detach`**, **`kind=detached`**. The comment wrapper matches the file type (`#`, `//`, `<!-- … -->`, `/* … */`, `--`, etc.); optional per-row **`marker_style`** in `files.json` overrides inference. Plain **`.json`** cannot carry comments—see [docs/configuration.md](docs/configuration.md).

**`sync`** options (see [docs/configuration.md](docs/configuration.md) for details): **`--dry-run`**, **`--force`** (overwrite locals that lack the clone marker), **`--all`** (consider every row except detached unless **`--include-detached`**), **`--include-status=a,b`** (comma-separated extra `sync_status` values to include), **`--include-detached`**.

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

CI runs **`shellcheck`**, **`bash scripts/ci-test.sh`** (orchestrates `tests/run-command-tests.sh` then `tests/run-lib-tests.sh`), builds a **`VERSION=0.0.0-ci`** `.deb`, and runs **`lintian --fail-on warning`**. To reproduce locally:

```bash
shellcheck -x bin/filesync commands/*.sh lib/*.sh scripts/ci-test.sh scripts/build-deb.sh tests/run-lib-tests.sh tests/run-command-tests.sh tests/harness-lib.sh tests/harness-command.sh tests/lib/*.sh tests/commands/*.sh
bash scripts/ci-test.sh --quiet
VERSION=0.0.0-ci bash scripts/build-deb.sh
lintian --fail-on warning filesync_0.0.0-ci_all.deb
```

## License

See [LICENSE](LICENSE).

## Embedding

You can keep this tree as a nested git repo, submodule, or subtree; for automation, install via `make install` or the release `.deb` so `filesync` is on `PATH`.
