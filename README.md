# filesync

Bash tooling to map and sync files across multiple git checkouts (e.g. a monorepo plus sibling service repos). State lives in the **consuming project** under `.filesync/`; this directory is the package source.

## Requirements

- `bash`, `jq`, `git`

## Usage

From the **project root** (a directory that contains `.filesync/`):

```bash
composer filesync check
composer filesync check --repo=emissions --file=HealthStatusService.php
composer filesync sync --file=Foo.php --dry-run
composer filesync list --repo=emissions
composer filesync list

# Or invoke the entrypoint directly:
bash filesync/bin/filesync check
bash filesync/bin/filesync sync --dry-run
```

Subcommands: `check`, `sync`, `list`, `repos`, `add`, `add-master`, `push`, `detach`, `attach`, `rm`, `repo`, `repo-edit`, `enable`, `disable`.

**`check`**, **`sync`**, **`repos`**, and **`list`** accept optional **`--repo=name`** (repo `name`). **`check`** and **`sync`** also accept **`--file=fragment`**: substring match on `local_path` or `repo_file_path` (case-sensitive). Combine **`--repo`** and **`--file`** to scope to one repo and matching paths.

Run `bash filesync/bin/filesync` with no arguments for a short usage line.

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

This tree may be a nested git repo, submodule, or subtree in a consumer. Point scripts at `filesync/bin/filesync` relative to that consumer’s root.
