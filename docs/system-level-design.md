# System-level filesync store (implementation reference)

Layout and command bootstrap matrix. User-facing docs: `docs/configuration.md` and `README.md`.

## Paths

| Item | Location |
|------|----------|
| System metadata home (default) | `$HOME/.filesync-root` (legacy `~/.filesync` may be renamed on first use) |
| Pointer override | `$XDG_CONFIG_HOME/filesync/system_home` — one line: absolute path; invalid paths fall back with a warning |
| Env override | `FILESYNC_HOME` — wins over pointer and default |
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
- `repo_name` — denormalized display; aligned via migrate and commands that touch project files (not `edit-repo --rename`, which updates global `repos.json` only).

## Runtime `CONFIG_FILE` (temp merged JSON)

Merged preferences, `repo_path_root` (effective anchor path), `repos`, `files` (rows normalized with `repo_id` / `repo_name`). Does not embed `collections`.

## Command → init mode

| Command | Init |
|---------|------|
| `add-repo`, `add-collection`, `edit-collection`, `remove-collection`, `list-repos`, `list-collections`, `progress`, `config`, `edit-repo` | system |
| `remove-repo`, `migrate`, `list-files`, `handle-missing`, `init` (special), `check`, `sync`, `add-file`, … | full (`filesync_command_init`) |

`list.sh` uses `filesync_command_init_system` for `list-repos` / `list-collections` and full init for `list-files`.

## Atomic writes

Global JSON updates use temp file + `mv`, typically under `flock` on `$FILESYNC_HOME/.lock`.
