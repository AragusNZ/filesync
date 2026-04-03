#!/usr/bin/env bash
# Sourced by bin/filesync after ROOT is set. Each filesync_route_* uses exec and does not return.

filesync_route_list() {
  case "${1-}" in
    "" | --*)
      exec "$ROOT/commands/list.sh" files "$@"
      ;;
    repos | repo | repositories | -r)
      shift
      exec "$ROOT/commands/list.sh" repos "$@"
      ;;
    files | file | -f)
      shift
      exec "$ROOT/commands/list.sh" files "$@"
      ;;
    collections | collection | col | -col)
      shift
      exec "$ROOT/commands/list.sh" collections "$@"
      ;;
    *)
      echo -e "${RED}Unknown list target: $1 (use repos, files, collections, -r, -f, or -col)${NC}" >&2
      exec "$ROOT/commands/help.sh" >&2
      exit 1
      ;;
  esac
}

filesync_route_add() {
  case "${1-}" in
    master | -m)
      shift
      exec "$ROOT/commands/add-master.sh" "$@"
      ;;
    clone | -c)
      shift
      exec "$ROOT/commands/add-clone.sh" "$@"
      ;;
    file | -f)
      shift
      exec "$ROOT/commands/add.sh" "$@"
      ;;
    *)
      exec "$ROOT/commands/add.sh" "$@"
      ;;
  esac
}

filesync_route_detach() {
  case "${1-}" in
    files-in-repo | -fir)
      shift
      exec "$ROOT/commands/detach-repo.sh" "$@"
      ;;
    file | -f)
      shift
      exec "$ROOT/commands/detach.sh" "$@"
      ;;
    *)
      exec "$ROOT/commands/detach.sh" "$@"
      ;;
  esac
}

filesync_route_attach() {
  case "${1-}" in
    files-in-repo | -fir)
      shift
      exec "$ROOT/commands/attach-repo.sh" "$@"
      ;;
    file | -f)
      shift
      exec "$ROOT/commands/attach.sh" "$@"
      ;;
    *)
      exec "$ROOT/commands/attach.sh" "$@"
      ;;
  esac
}

filesync_route_remove() {
  case "${1-}" in
    repo | -r)
      shift
      exec "$ROOT/commands/remove-repo.sh" "$@"
      ;;
    collection | -col)
      shift
      exec "$ROOT/commands/remove-collection.sh" "$@"
      ;;
    file | -f)
      shift
      exec "$ROOT/commands/rm.sh" "$@"
      ;;
    *)
      exec "$ROOT/commands/rm.sh" "$@"
      ;;
  esac
}

filesync_route_new() {
  case "${1-}" in
    repo | -r)
      shift
      exec "$ROOT/commands/add-repo.sh" "$@"
      ;;
    collection | -col)
      shift
      exec "$ROOT/commands/add-collection.sh" "$@"
      ;;
    *)
      echo -e "${RED}Usage: filesync new repo|collection ...${NC}" >&2
      exit 1
      ;;
  esac
}

filesync_route_edit() {
  case "${1-}" in
    repo | -r)
      shift
      exec "$ROOT/commands/edit-repo.sh" "$@"
      ;;
    collection | -col)
      shift
      exec "$ROOT/commands/edit-collection.sh" "$@"
      ;;
    *)
      echo -e "${RED}Usage: filesync edit repo|collection ...${NC}" >&2
      exit 1
      ;;
  esac
}

filesync_route_info() {
  if [[ $# -eq 0 ]]; then
    echo -e "${RED}Usage: filesync info [file | -f] <local-path> [--fix-marker]${NC}" >&2
    echo "       filesync i <local-path>   (same; optional word: file or -f)" >&2
    echo "See: filesync info file --help  or  filesync info --help" >&2
    exit 1
  fi
  case "$1" in
    -h | --help)
      exec "$ROOT/commands/info-file.sh" --help
      ;;
    file | -f)
      shift
      ;;
  esac
  exec "$ROOT/commands/info-file.sh" "$@"
}
