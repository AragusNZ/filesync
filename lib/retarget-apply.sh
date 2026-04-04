#!/usr/bin/env bash
# Shared jq updates for retarget clone / retarget master.

_LIB_RT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${RED:-}" ]] && [[ -r "${_LIB_RT}/colors.sh" ]]; then
  # shellcheck source=/dev/null
  source "${_LIB_RT}/colors.sh"
fi

# Args: new_repo_file_path (repo-relative). Returns 1 if invalid.
filesync_retarget_new_rfp_must_be_relative() {
  local new_rfp="${1:?}"
  case "$new_rfp" in
    /* | ../* | */../* | .. | */..)
      echo -e "${RED}<new_repo_file_path> must be repo-relative (no leading / or .. segments).${NC}" >&2
      return 1
      ;;
  esac
}

# Args: files_json local_path new_rfp do_move now_iso
filesync_retarget_apply_jq_clone() {
  local fj="$1" lp="$2" nrp="$3" do_move="$4" now="$5"
  if [[ "$do_move" == true ]]; then
    jq --arg lp "$lp" --arg nrp "$nrp" --arg now "$now" \
      'map(if .local_path == $lp then . + {repo_file_path: $nrp, local_path: $nrp, sync_status: "sync_required", last_check_at: $now} else . end)' "$fj" >"${fj}.tmp"
  else
    jq --arg lp "$lp" --arg nrp "$nrp" --arg now "$now" \
      'map(if .local_path == $lp then . + {repo_file_path: $nrp, sync_status: "sync_required", last_check_at: $now} else . end)' "$fj" >"${fj}.tmp"
  fi
  mv "${fj}.tmp" "$fj"
}

# Args: files_json old_rfp new_rfp repo_id do_move now_iso
filesync_retarget_apply_jq_master_union() {
  local fj="$1" oldrfp="$2" nrp="$3" rid="$4" do_move="$5" now="$6"
  if [[ "$do_move" == true ]]; then
    jq --arg oldrfp "$oldrfp" --arg nrp "$nrp" --arg rid "$rid" --arg now "$now" \
      'map(
        if (.repo_file_path == $oldrfp) and (($rid != "") and ($rid != "null") and (.repo_id == $rid))
        then . + {repo_file_path: $nrp, local_path: $nrp, sync_status: "sync_required", last_check_at: $now}
        else . end
      )' "$fj" >"${fj}.tmp"
  else
    jq --arg oldrfp "$oldrfp" --arg nrp "$nrp" --arg rid "$rid" --arg now "$now" \
      'map(
        if (.repo_file_path == $oldrfp) and (($rid != "") and ($rid != "null") and (.repo_id == $rid))
        then . + {repo_file_path: $nrp, sync_status: "master_file_moved", last_check_at: $now}
        else . end
      )' "$fj" >"${fj}.tmp"
  fi
  mv "${fj}.tmp" "$fj"
}
