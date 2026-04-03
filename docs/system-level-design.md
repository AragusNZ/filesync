# System-level filesync store (implementation reference)

Layout and command bootstrap matrix. User-facing docs: `docs/configuration.md` and `README.md`.

## Paths

| Item | Location |
|------|----------|
| System metadata home (default) | `$HOME/.filesync-root` |
| Env override | `FILESYNC_HOME` — absolute path; intended for tests/CI (not per-project `.env`) |
| Optional path anchor | `FILESYNC_REPO_PATH_ANCHOR` — overrides `$HOME` for resolving relative `path` in `repos.json` (tests) |
| `system.json` | `$FILESYNC_HOME/system.json` — e.g. `{ "version": 2 }` |
| Global repos | `$FILESYNC_HOME/repos.json` — array with `id`, `name`, `url`, `path`, `branch`, flags |
| Global collections | `$FILESYNC_HOME/collections.json` |
| Preferences | `$FILESYNC_HOME/preferences.json` |
| Lock file | `$FILESYNC_HOME/.lock` — `flock` for mutating commands |
| Project | `$PROJECT_ROOT/.filesync/files.json` (and optional legacy files pre-migrate) |

## Repo object

- `id` — stable UUID string (required after `migrate` / new repos).
- `name`, `url`, `path`, `branch` — as documented.
- `check_sync_enabled`, `mirror_in_enabled` — default true if omitted.

## File row object

- `repo_id` — references `repos[].id`.
- `repo_name` — denormalized display; aligned via migrate and commands that touch project files (not `edit repo --rename`, which updates global `repos.json` only).

## Runtime `CONFIG_FILE` (temp merged JSON)

Merged preferences, `repo_path_root` (effective anchor path), `repos`, `files` (rows normalized with `repo_id` / `repo_name`). Does not embed `collections`.

## Command → init mode

| Command | Init |
|---------|------|
| `new repo`, `new collection`, `edit collection`, `remove collection`, `list repos`, `list collections`, `config`, `edit repo` | system |
| `init` | Custom bootstrap: writes target **`.filesync/files.json`**, ensures system store, optional global **`repos.json`** append under **`flock`** (does not call `filesync_command_init`). |
| `remove repo`, `migrate`, `list files`, `handle-missing`, `check`, `sync`, `info`, `add file`, … | `filesync_command_init` (project resolution + assembled state) |

`list.sh` uses `filesync_command_init_system` for `repos` / `collections` (internal argv) and full init for `files`.

## Atomic writes

Global JSON is usually replaced with temp file + `mv`. `flock` on `$FILESYNC_SYSTEM_HOME/.lock` (same dir as the store) serializes several mutators (`config` set, `new repo`, `edit repo`, `migrate`, `remove repo`, `init` global repo step); some collection updates use temp + `mv` only.
