#!/usr/bin/env bash
# Resolve comment wrapper style for filesync markers from path (extension / basename).

# Valid style keys: line_slash line_hash line_dash block_c html
filesync_marker_style_valid() {
  case "${1:-}" in
    line_slash | line_hash | line_dash | block_c | html) return 0 ;;
    *) return 1 ;;
  esac
}

# Args: relative_or_basename_path
# Prints one style key. Default for unknown extensions: line_hash.
filesync_marker_style_for_path() {
  local p="${1:?}"
  local base="${p##*/}"
  local ext=""
  [[ "$base" == *.* ]] && ext="${base##*.}"
  local el
  el=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')

  case "$base" in
    Dockerfile | Dockerfile.* | dockerfile)
      printf '%s\n' line_hash
      return
      ;;
    Makefile | makefile | GNUmakefile)
      printf '%s\n' line_hash
      return
      ;;
  esac

  case "$el" in
    html | htm | xml | svg | vue)
      printf '%s\n' html
      ;;
    css | scss)
      printf '%s\n' block_c
      ;;
    sql | hs)
      printf '%s\n' line_dash
      ;;
    py | rb | sh | bash | yaml | yml | toml | ini | plist | zsh | fish | ps1 | \
      md | markdown | txt | log | conf | cfg | env | gitignore | dockerignore)
      printf '%s\n' line_hash
      ;;
    js | jsx | mjs | cjs | ts | tsx | java | go | rs | php | c | h | cpp | hpp | cc | cxx | \
      cs | swift | kt | kts | scala | dart | gradle | groovy)
      printf '%s\n' line_slash
      ;;
    *)
      printf '%s\n' line_hash
      ;;
  esac
}

# Args: local_path marker_style_json
# marker_style_json: row field value or empty / "null" — if set and valid, use it; else extension map.
filesync_marker_style_resolve() {
  local path="${1:?}"
  local override="${2:-}"
  override="${override//$'\r'/}"
  override="${override//$'\n'/}"
  if [[ -n "$override" && "$override" != "null" ]] && filesync_marker_style_valid "$override"; then
    printf '%s\n' "$override"
    return
  fi
  filesync_marker_style_for_path "$path"
}
