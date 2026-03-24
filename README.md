# filesync

Bash tooling to map and sync files across multiple git checkouts (e.g. a monorepo plus sibling service repos). State lives in the **consuming project** under `.filesync/`; this directory is the package source.

## Requirements

- `bash`, `jq`, `git`

## Installing via Composer

From your PHP project root:

```bash
composer require aragusnz/filesync
```

Composer installs the package under `vendor/aragusnz/filesync` and links the CLI to `vendor/bin/filesync`.

## Usage

From the **project root** (a directory that contains `.filesync/`):

```bash
vendor/bin/filesync check
vendor/bin/filesync check --repo=emissions --file=HealthStatusService.php
vendor/bin/filesync sync --file=Foo.php --dry-run
vendor/bin/filesync list --repo=emissions
vendor/bin/filesync list
```

Using Composer’s binary resolution (same effect when `vendor/bin` is not on your `PATH`):

```bash
composer exec filesync -- check
composer exec filesync -- sync --dry-run
```

Optional project script (in your app’s `composer.json`): `"scripts": { "filesync": "filesync" }` — then run `composer run filesync -- check` (note `--` before arguments).

**Direct / git checkout:** invoke `bin/filesync` from this tree (or `bash path/to/filesync/bin/filesync …`).

Subcommands: `check`, `sync`, `list`, `repos`, `add`, `add-master`, `push`, `detach`, `attach`, `rm`, `repo`, `repo-edit`, `enable`, `disable`.

**`check`**, **`sync`**, **`repos`**, and **`list`** accept optional **`--repo=name`** (repo `name`). **`check`** and **`sync`** also accept **`--file=fragment`**: substring match on `local_path` or `repo_file_path` (case-sensitive). Combine **`--repo`** and **`--file`** to scope to one repo and matching paths.

Run `vendor/bin/filesync` (or `bin/filesync`) with no arguments for a short usage line.

## Layout

| Path | Role |
|------|------|
| `bin/filesync` | Dispatcher |
| `commands/*.sh` | One script per subcommand |
| `lib/*.sh` | Resolve project, merge config, assemble state JSON, paths, status |
| `share/defaults/config.default.json` | Shallow-merge defaults for `.filesync/config.json` |

## User data: `.filesync/`

| File | Content |
|------|---------|
| `config.json` | JSON object (partial); merged over package defaults |
| `repos.json` | JSON **array** of repo objects (`name`, `url`, `path`, `branch`, …) |
| `files.json` | JSON **array** of file rows |

Basenames are defined in `lib/data-names.sh` if you need to change them in a fork.

Discovery: walk parents from the current working directory until a directory containing `.filesync` is found; that directory’s parent is the **project root**. Overrides: `FILESYNC_PROJECT_ROOT` or `FILESYNC_DIR` (see [docs/configuration.md](docs/configuration.md)).

## Docs

- [Configuration and environment](docs/configuration.md)

## Embedding

This tree may be installed via Composer, or used as a nested git repo, submodule, or subtree. Point automation at `vendor/bin/filesync` (Composer) or `filesync/bin/filesync` relative to your project.

## Packagist

After tagging releases (e.g. `v1.0.0`), submit the repository URL at [packagist.org/packages/submit](https://packagist.org/packages/submit) and connect the Git webhook for automatic updates.
