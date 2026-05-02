#!/usr/bin/env bash
# Shared filesync marker helpers (sourced; no set -e at top level).
# Inner payload format: filesync kind=master|clone|detached [path=...] [repo=...] [repo_id=...] [detached=true on kind=clone]

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
          case "$tok" in
            repo="${old_name}") tok="repo=${new_name}"; changed=1 ;;
          esac
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

# Replace repo_id=old_id with repo_id=new_id in the first filesync marker line.
# Returns 0 if the file was rewritten, 1 if skipped (missing file, no marker, no matching repo_id token).
filesync_marker_replace_repo_id_in_file() {
  local file_path="${1:?}" old_id="${2:?}" new_id="${3:?}"
  [[ -f "$file_path" ]] || return 1
  local tmp st line new_inner tok did=0 changed=0
  tmp="$(mktemp)"
  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $did -eq 0 && "$line" == *"filesync kind="* ]]; then
      if filesync_marker_parse_line "$line"; then
        did=1
        new_inner=""
        for tok in $FILESYNC_M_INNER; do
          case "$tok" in
            repo_id="${old_id}") tok="repo_id=${new_id}"; changed=1 ;;
          esac
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

has_detached_file_sync_marker() {
  local f="$1"
  grep -q "filesync kind=" "$f" && grep -qE 'kind=detached([[:space:]]|$)' "$f"
}

has_detached_clone_file_sync_marker() {
  local f="$1"
  grep -q "filesync kind=" "$f" && grep -q 'detached=true' "$f" && grep -qE 'kind=clone([[:space:]]|$)' "$f"
}

# Reads the first line containing a filesync marker. If payload is kind=clone, sets
# FILESYNC_CLONE_M_PATH, FILESYNC_CLONE_M_REPO, FILESYNC_CLONE_M_REPO_ID (empty if absent) and returns 0.
# Otherwise returns 1. Requires a regular file.
# shellcheck disable=SC2034  # *_PATH/REPO/REPO_ID are outputs for callers
filesync_marker_read_clone_tokens_from_file() {
  FILESYNC_CLONE_M_PATH=""
  FILESYNC_CLONE_M_REPO=""
  FILESYNC_CLONE_M_REPO_ID=""
  [[ -f "${1:-}" ]] || return 1
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *"filesync kind="* ]] || continue
    filesync_marker_parse_line "$line" || continue
    grep -qE 'kind=clone([[:space:]]|$)' <<<"$FILESYNC_M_INNER" || return 1
    local tok
    for tok in $FILESYNC_M_INNER; do
      case "$tok" in
        path=*) FILESYNC_CLONE_M_PATH="${tok#path=}" ;;
        repo=*) FILESYNC_CLONE_M_REPO="${tok#repo=}" ;;
        repo_id=*) FILESYNC_CLONE_M_REPO_ID="${tok#repo_id=}" ;;
      esac
    done
    return 0
  done <"$1"
  return 1
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

# Prepend a kind=master marker as the first line. Fails if the file is missing
# or already contains any filesync marker. style_hint_path drives comment style
# (extension map) when not inferrable from an existing marker line.
prepend_master_marker_to_file() {
  local file_path="${1:?}"
  local style_hint_path="${2:-$file_path}"
  [[ -f "$file_path" ]] || return 1
  if has_any_file_sync_marker "$file_path"; then
    return 1
  fi
  local st line tmp
  st=$(filesync_marker_style_resolve "$style_hint_path" "")
  line="$(filesync_marker_format_line "$st" "filesync kind=master")"
  tmp="$(mktemp)"
  if filesync_marker_preserve_first_line "$file_path" "$style_hint_path" "$st"; then
    local first_line second_line hint_lc file_lc
    first_line=""
    second_line=""
    {
      IFS= read -r first_line || true
      IFS= read -r second_line || true
    } <"$file_path"
    hint_lc="$(printf '%s' "$style_hint_path" | tr '[:upper:]' '[:lower:]')"
    file_lc="$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')"

    # PHP linting often expects a blank line after the opening tag.
    if [[ "$first_line" == "<?php"* && "$st" == "line_slash" && ( "$hint_lc" == *.php || "$file_lc" == *.php ) ]]; then
      local second_trim
      second_trim="${second_line//$'\r'/}"
      second_trim="${second_trim#"${second_trim%%[![:space:]]*}"}"
      second_trim="${second_trim%"${second_trim##*[![:space:]]}"}"
      {
        printf '%s\n' "$first_line"
        if [[ -z "$second_trim" ]]; then
          printf '\n'
          printf '%s\n' "$line"
          tail -n +3 "$file_path"
        else
          printf '\n'
          printf '%s\n' "$line"
          tail -n +2 "$file_path"
        fi
      } >"$tmp" || {
        rm -f "$tmp"
        return 1
      }
      mv "$tmp" "$file_path"
      return 0
    fi

    {
      printf '%s\n' "$first_line"
      printf '%s\n' "$line"
      tail -n +2 "$file_path"
    } >"$tmp" || {
      rm -f "$tmp"
      return 1
    }
    mv "$tmp" "$file_path"
    return 0
  fi
  { printf '%s\n' "$line"; cat -- "$file_path"; } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$file_path"
}

# Returns 0 when marker insertion should preserve line 1.
# Rules protect required first-line directives in known formats.
filesync_marker_preserve_first_line() {
  local file_path="${1:?}" style_hint_path="${2:?}" st="${3:?}"
  local first_line hint_lc file_lc
  IFS= read -r first_line <"$file_path" || return 1
  hint_lc="$(printf '%s' "$style_hint_path" | tr '[:upper:]' '[:lower:]')"
  file_lc="$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')"

  # Shebang must stay first for executable scripts.
  if [[ "$first_line" == '#!'* && ( "$st" == "line_hash" || "$st" == "line_slash" ) ]]; then
    return 0
  fi
  # PHP opening tag should stay first in PHP source.
  if [[ "$first_line" == "<?php"* && "$st" == "line_slash" && ( "$hint_lc" == *.php || "$file_lc" == *.php ) ]]; then
    return 0
  fi
  # XML declaration is expected first in XML-family documents.
  if [[ "$first_line" == "<?xml"* && "$st" == "html" ]]; then
    return 0
  fi
  # CSS charset declaration should remain the first statement.
  if [[ "$first_line" =~ ^[[:space:]]*@charset[[:space:]] && "$st" == "block_c" && ( "$hint_lc" == *.css || "$hint_lc" == *.scss || "$file_lc" == *.css || "$file_lc" == *.scss ) ]]; then
    return 0
  fi
  return 1
}

render_clone_from_master_file() {
  local master_file="$1"
  local master_repo_path="$2"
  local repo_name="$3"
  local output_file="$4"
  local repo_id="${5:-}"
  local inner="filesync kind=clone path=${master_repo_path} repo=${repo_name}"
  if [[ -n "$repo_id" ]]; then
    inner="${inner} repo_id=${repo_id}"
  fi

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

  local repo_id="${6:-}"
  if [[ -n "$repo_file_path" && -n "$repo_name" ]]; then
    inner="filesync kind=detached path=${repo_file_path} repo=${repo_name}"
    if [[ -n "$repo_id" ]]; then
      inner="${inner} repo_id=${repo_id}"
    fi
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

# Like strip_file_sync_marker_lines, but keeps lines whose first marker payload is kind=master
# (e.g. when the local path is the same file as the repo master, or a shared master copy).
strip_non_master_filesync_marker_lines() {
  local input_file="$1"
  local output_file="$2"
  : >"$output_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"filesync kind="* ]]; then
      if filesync_marker_parse_line "$line" && grep -qE 'kind=master([[:space:]]|$)' <<< "$FILESYNC_M_INNER"; then
        printf '%s\n' "$line" >>"$output_file"
      fi
    else
      printf '%s\n' "$line" >>"$output_file"
    fi
  done <"$input_file"
}

# Alias for clarity (same implementation).
strip_filesync_marker_lines() {
  strip_file_sync_marker_lines "$1" "$2"
}
