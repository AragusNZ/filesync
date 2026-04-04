#!/usr/bin/env bash
# Compare this install to the latest GitHub release; if newer exists, prompt to apply (git + make install or .deb).
# Usage: update.sh [-y]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILESYNC_PKG_ROOT="$(cd "${_CMD_ROOT}/.." && pwd)"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/cli-help.sh"
FILESYNC_CMD_USAGE='Usage: filesync update [-y|--yes]'
if filesync_argv_wants_help "$@"; then
	cat <<EOF
${FILESYNC_CMD_USAGE}

Compare this filesync install to the latest GitHub release. If a newer version exists and the install
layout supports it (git clone or unpacked .deb), you get a prompt to upgrade (git pull + make install,
or install the release .deb).

Options:

  -y, --yes    If an update exists, apply it without prompting.

Environment:

  FILESYNC_INSTALL_PREFIX    Override PREFIX when git+make install autodetection is wrong.
EOF
	exit 0
fi
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/log.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/deps.sh"

filesync_require_jq

REPO_SLUG="AragusNZ/filesync"
YES=false

while [[ $# -gt 0 ]]; do
	case "$1" in
		-y | --yes) YES=true; shift ;;
		*)
			filesync_unexpected_arg_stderr "$1" "$FILESYNC_CMD_USAGE"
			exit 1
			;;
	esac
done

CURRENT="unknown"
if [[ -r "${FILESYNC_PKG_ROOT}/share/VERSION" ]]; then
	CURRENT="$(tr -d '\r\n' <"${FILESYNC_PKG_ROOT}/share/VERSION")"
fi

filesync_download() {
	local url="$1" out="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$out" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$out" "$url"
	else
		echo -e "${RED}filesync update: install curl or wget to check releases.${NC}" >&2
		exit 1
	fi
}

API_URL="https://api.github.com/repos/${REPO_SLUG}/releases/latest"
TMP_JSON="$(mktemp)"
DEB_FILE=""
trap 'rm -f "${TMP_JSON}" "${DEB_FILE}"' EXIT

if command -v curl >/dev/null 2>&1; then
	_http="$(curl -sS -o "$TMP_JSON" -w "%{http_code}" "$API_URL" || printf '%s' "000")"
	if [[ "$_http" != "200" ]]; then
		if [[ "$_http" == "404" ]]; then
			echo -e "${RED}filesync update: no GitHub releases yet (404).${NC}" >&2
		else
			echo -e "${RED}filesync update: could not fetch ${API_URL} (HTTP ${_http}).${NC}" >&2
		fi
		exit 1
	fi
else
	if ! filesync_download "$API_URL" "$TMP_JSON" 2>/dev/null; then
		echo -e "${RED}filesync update: could not fetch ${API_URL}${NC}" >&2
		exit 1
	fi
fi

TAG_RAW="$(jq -r '.tag_name // empty' "$TMP_JSON")"
if [[ -z "$TAG_RAW" || "$TAG_RAW" == "null" ]]; then
	echo -e "${RED}filesync update: unexpected API response (no tag).${NC}" >&2
	exit 1
fi

LATEST="${TAG_RAW#v}"
DEB_URL="$(jq -r '(.assets // [])[] | select(.name | test("^filesync_.+_all\\.deb$")) | .browser_download_url' "$TMP_JSON" | head -n1)"

echo -e "${BOLD}${WHITE}FILESYNC version${NC}  ${BOLD}${WHITE}${CURRENT}${NC}  (this install)" >&2
echo -e "${BOLD}${WHITE}Latest release${NC}    ${BOLD}${WHITE}${LATEST}${NC}  (${REPO_SLUG})" >&2

up_to_date=false
if [[ "$CURRENT" == "$LATEST" ]]; then
	up_to_date=true
elif [[ "$CURRENT" != "unknown" ]] && command -v dpkg >/dev/null 2>&1; then
	if dpkg --compare-versions "$LATEST" le "$CURRENT" 2>/dev/null; then
		up_to_date=true
	fi
fi

if [[ "$up_to_date" == true ]]; then
	echo -e "${GREEN}You are on the latest release (or newer than the published release).${NC}" >&2
	exit 0
fi

if [[ "$CURRENT" == "unknown" ]]; then
	echo -e "${YELLOW}Could not read installed version; latest published release is ${LATEST}.${NC}" >&2
else
	echo -e "${YELLOW}A newer release is available (${CURRENT} -> ${LATEST}).${NC}" >&2
fi

can_apply=false
if [[ -d "${FILESYNC_PKG_ROOT}/.git" ]]; then
	can_apply=true
elif [[ -n "$DEB_URL" ]]; then
	can_apply=true
fi

if [[ "$can_apply" != true ]]; then
	echo "" >&2
	echo "This install cannot be updated automatically (not a git checkout of filesync and no matching release .deb). See:" >&2
	echo "  https://github.com/${REPO_SLUG}/releases/latest" >&2
	exit 0
fi

if [[ "$YES" != true ]]; then
	read -rp "Apply update now? [y/N] " ans || true
	if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
		echo "Aborted." >&2
		exit 0
	fi
fi

if [[ -d "${FILESYNC_PKG_ROOT}/.git" ]]; then
	PREFIX="${FILESYNC_INSTALL_PREFIX:-$(dirname "$(dirname "${FILESYNC_PKG_ROOT}")")}"
	cd "${FILESYNC_PKG_ROOT}"
	git pull
	if command -v sudo >/dev/null 2>&1; then
		sudo make install PREFIX="${PREFIX}"
	else
		make install PREFIX="${PREFIX}"
	fi
	echo -e "${GREEN}Updated from git and reinstalled (PREFIX=${PREFIX}).${NC}" >&2
	exit 0
fi

if [[ -z "$DEB_URL" ]]; then
	echo -e "${RED}No .deb on this release; cannot install automatically.${NC}" >&2
	exit 1
fi

DEB_FILE="$(mktemp "${TMPDIR:-/tmp}/filesync.XXXXXX.deb")"
filesync_download "$DEB_URL" "$DEB_FILE"

if command -v sudo >/dev/null 2>&1; then
	sudo dpkg -i "$DEB_FILE"
else
	dpkg -i "$DEB_FILE"
fi

echo -e "${GREEN}Installed $(basename "$DEB_URL")${NC}" >&2
