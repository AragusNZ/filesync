#!/usr/bin/env bash
# Shared filesync marker helpers (sourced; no set -e at top level).
# Inner payload format: filesync kind=master|clone|detached [path=...] [repo=...] [detached=true on kind=clone]

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/marker-style.sh"

filesync_marker_parse_line() {
  FILESYNC_M_STYLE=""
  FILESYNC_M_INNER=""
  local line="${1:-}"
  line="${line//$'\r'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  [[ "$line" == *"filesync kind="* ]] || return 1

  local rest="$line" body

  if [[ "$rest" == "<!--"* ]]; then
    rest="${rest#<!--}"
    rest="${rest%-->*}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    rest="${rest%"${rest##*[![:space:]]}"}"
    if [[ "$rest" == *"filesync kind="* ]]; then
      FILESYNC_M_STYLE=html
      FILESYNC_M_INNER="$rest"
      return 0
    fi
    rest="$line"
  fi

  if [[ "$rest" == "/*"* ]]; then
    body="${rest#/\*}"
    body="${body%\*/}"
    body="${body#"${body%%[![:space:]]*}"}"
    body="${body%"${body##*[![:space:]]}"}"
    if [[ "$body" == *"filesync kind="* ]]; then
      FILESYNC_M_STYLE=block_c
      FILESYNC_M_INNER="$body"
      return 0
    fi
  fi

  rest="$line"
  if [[ "$rest" == "//"* ]]; then
    body="${rest#//}"
    body="${body#"${body%%[![:space:]]*}"}"
    if [[ "$body" == *"filesync kind="* ]]; then
      FILESYNC_M_STYLE=line_slash
      FILESYNC_M_INNER="$body"
      return 0
    fi
  fi

  rest="$line"
  if [[ "$rest" == "#"* ]]; then
    body="${rest#\#}"
    body="${body#"${body%%[![:space:]]*}"}"
    if [[ "$body" == *"filesync kind="* ]]; then
      FILESYNC_M_STYLE=line_hash
      FILESYNC_M_INNER="$body"
      return 0
    fi
  fi

  rest="$line"
  if [[ "$rest" == "--"* ]]; then
    body="${rest#--}"
    body="${body#"${body%%[![:space:]]*}"}"
    if [[ "$body" == *"filesync kind="* ]]; then
      FILESYNC_M_STYLE=line_dash
      FILESYNC_M_INNER="$body"
      return 0
    fi
  fi

  FILESYNC_M_STYLE=""
  FILESYNC_M_INNER="$line"
  return 0
}

filesync_marker_format_line() {
  local style="${1:?}" inner="${2:?}"
  case "$style" in
    line_slash) printf '// %s\n' "$inner" ;;
    line_hash) printf '# %s\n' "$inner" ;;
    line_dash) printf -- '-- %s\n' "$inner" ;;
    block_c) printf '/* %s */\n' "$inner" ;;
    html) printf '<!-- %s -->\n' "$inner" ;;
    *) printf '# %s\n' "$inner" ;;
  esac
}

# Apply default style when parse left FILESYNC_M_STYLE empty (raw inner line).
filesync_marker_effective_style() {
  local file_path="${1:?}"
  local ov="${2:-}"
  if [[ -n "${FILESYNC_M_STYLE:-}" ]]; then
    printf '%s\n' "$FILESYNC_M_STYLE"
  else
    filesync_marker_style_resolve "$file_path" "$ov"
  fi
}

# Replace repo=old_name with repo=new_name in the first filesync marker (clone/detached).
# Returns 0 if the file was rewritten, 1 if skipped (missing file, no marker, no matching repo token).
filesync_marker_rename_repo_in_file() {
  local file_path="${1:?}" old_name="${2:?}" new_name="${3:?}"
  [[ -f "$file_path" ]] || return 1
  local tmp st line new_inner tok did=0 changed=0
  tmp="$(mktemp)"
  # Loop stdin is $file_path; writes go only to $tmp, then mv — not a read+write race on one fd.
  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $did -eq 0 && "$line" == *"filesync kind="* ]]; then
      if filesync_marker_parse_line "$line"; then
        did=1
        new_inner=""
        for tok in $FILESYNC_M_INNER; do
          if [[ "$tok" == "repo=${old_name}" ]]; then
            tok="repo=${new_name}"
            changed=1
          fi
          new_inner="${new_inner:+$new_inner }${tok}"
        done
        if [[ $changed -eq 1 ]]; then
          st=$(filesync_marker_effective_style "$file_path" "")
          line="$(filesync_marker_format_line "$st" "$new_inner")"
        fi
      fi
    fi
    printf '%s\n' "$line" >>"$tmp"
  done <"$file_path"
  if [[ $changed -ne 1 ]]; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$file_path"
  return 0
}

# Args: input output new_inner file_hint [marker_style_override]
filesync_marker_transform_file() {
  local input_file="${1:?}" output_file="${2:?}" new_inner="${3:?}" file_hint="${4:?}"
  local ov="${5:-}"
  local did=0 line st
  : >"$output_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $did -eq 0 && "$line" == *"filesync kind="* ]]; then
      if filesync_marker_parse_line "$line"; then
        st=$(filesync_marker_effective_style "$file_hint" "$ov")
        line="$(filesync_marker_format_line "$st" "$new_inner")"
        did=1
      fi
    fi
    printf '%s\n' "$line" >>"$output_file"
  done <"$input_file"
  [[ $did -eq 1 ]]
}

has_any_file_sync_marker() {
  grep -q "filesync kind=" "$1"
}

has_master_file_sync_marker() {
  local f="$1"
  grep -q "filesync kind=" "$f" && grep -qE 'kind=master([[:space:]]|$)' "$f"
}

has_clone_file_sync_marker() {
  local f="$1"
  grep -q "filesync kind=" "$f" && grep -qE 'kind=clone([[:space:]]|$)' "$f"
}

has_detached_clone_file_sync_marker() {
  local f="$1"
  grep -q "filesync kind=" "$f" && grep -q 'detached=true' "$f" && grep -qE 'kind=clone([[:space:]]|$)' "$f"
}

# Mark an on-disk clone while keeping kind=clone (legacy helper; unused by default flow).
replace_clone_with_detached_marker() {
  local file="$1"
  if ! has_clone_file_sync_marker "$file"; then
    return 1
  fi
  if has_detached_clone_file_sync_marker "$file"; then
    return 0
  fi
  local tmp hint st did=0 new_inner
  tmp="$(mktemp)"
  hint="$file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $did -eq 0 && "$line" == *"filesync kind="* ]]; then
      if filesync_marker_parse_line "$line"; then
        new_inner="${FILESYNC_M_INNER} detached=true"
        new_inner="${new_inner//  / }"
        st=$(filesync_marker_effective_style "$hint" "")
        line="$(filesync_marker_format_line "$st" "$new_inner")"
        did=1
      fi
    fi
    printf '%s\n' "$line" >>"$tmp"
  done <"$file"
  mv "$tmp" "$file"
  return 0
}

# Optional 3rd arg: marker_style row override (when inner has no comment wrapper).
render_master_marker_file() {
  local input_file="$1"
  local output_file="$2"
  local style_ov="${3:-}"
  local hint="${input_file}"

  if has_clone_file_sync_marker "$input_file"; then
    filesync_marker_transform_file "$input_file" "$output_file" "filesync kind=master" "$hint" "$style_ov"
    return 0
  fi

  if has_master_file_sync_marker "$input_file"; then
    cp "$input_file" "$output_file"
    return 0
  fi

  if has_any_file_sync_marker "$input_file"; then
    filesync_marker_transform_file "$input_file" "$output_file" "filesync kind=master" "$hint" "$style_ov"
    return 0
  fi

  return 1
}

render_clone_from_master_file() {
  local master_file="$1"
  local master_repo_path="$2"
  local repo_name="$3"
  local output_file="$4"
  local inner="filesync kind=clone path=${master_repo_path} repo=${repo_name}"

  filesync_marker_transform_file "$master_file" "$output_file" "$inner" "$master_file"
}

# Optional 5th arg: marker_style row override.
render_detached_marker_file() {
  local input_file="$1"
  local output_file="$2"
  local repo_file_path="${3:-}"
  local repo_name="${4:-}"
  local style_ov="${5:-}"
  local inner="filesync kind=detached"

  if [[ -n "$repo_file_path" && -n "$repo_name" ]]; then
    inner="filesync kind=detached path=${repo_file_path} repo=${repo_name}"
  fi

  if has_any_file_sync_marker "$input_file"; then
    filesync_marker_transform_file "$input_file" "$output_file" "$inner" "$input_file" "$style_ov"
    return 0
  fi

  return 1
}

strip_file_sync_marker_lines() {
  local input_file="$1"
  local output_file="$2"
  awk 'index($0, "filesync kind=") == 0 { print }' "$input_file" >"$output_file"
}

# Alias for clarity (same implementation).
strip_filesync_marker_lines() {
  strip_file_sync_marker_lines "$1" "$2"
}
