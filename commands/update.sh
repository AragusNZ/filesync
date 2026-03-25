#!/usr/bin/env bash
# Check for a newer upstream release and optionally apply an update (.deb or git + make install).
# Usage: update.sh [--check] [--apply] [-y|--yes]

set -euo pipefail

_CMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILESYNC_PKG_ROOT="$(cd "${_CMD_ROOT}/.." && pwd)"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/log.sh"
# shellcheck source=/dev/null
source "${FILESYNC_PKG_ROOT}/lib/deps.sh"

filesync_require_jq

REPO_SLUG="AragusNZ/filesync"
APPLY=false
YES=false

while [[ $# -gt 0 ]]; do
	case "$1" in
		--check) shift ;;
		--apply) APPLY=true; shift ;;
		-y | --yes) YES=true; shift ;;
		-h | --help)
			echo "Usage: filesync update [--check] [--apply] [-y|--yes]" >&2
			echo "  --check   Only show current vs latest (default if no --apply)" >&2
			echo "  --apply   Install update (git pull + make install, or latest .deb)" >&2
			echo "  -y        Do not prompt before --apply" >&2
			echo "Env: FILESYNC_INSTALL_PREFIX (for git+make install PREFIX when autodetection is wrong)" >&2
			exit 0
			;;
		*)
			echo -e "${RED}Unknown option: $1${NC}" >&2
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

echo -e "${CYAN}filesync version${NC}  ${WHITE}${CURRENT}${NC}  (this install)" >&2
echo -e "${CYAN}Latest release${NC}    ${WHITE}${LATEST}${NC}  (${REPO_SLUG})" >&2

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

if [[ "$APPLY" != true ]]; then
	echo "" >&2
	if [[ -d "${FILESYNC_PKG_ROOT}/.git" ]]; then
		PREFIX_HINT="${FILESYNC_INSTALL_PREFIX:-$(dirname "$(dirname "${FILESYNC_PKG_ROOT}")")}"
		echo "This tree is a git checkout. To update:" >&2
		echo "  cd ${FILESYNC_PKG_ROOT} && git pull && sudo make install PREFIX=${PREFIX_HINT}" >&2
		echo "(Set FILESYNC_INSTALL_PREFIX if you originally used a different PREFIX.)" >&2
	else
		if [[ -n "$DEB_URL" ]]; then
			echo "Debian/Ubuntu (.deb from GitHub Releases):" >&2
			echo "  curl -fsSLO '$DEB_URL'" >&2
			echo "  sudo apt install -y ./\"$(basename "$DEB_URL")\"" >&2
			echo "Or run: filesync update --apply" >&2
		else
			echo "No .deb asset found on the latest release; see:" >&2
			echo "  https://github.com/${REPO_SLUG}/releases/latest" >&2
		fi
	fi
	exit 0
fi

# --apply
if [[ "$YES" != true ]]; then
	read -rp "Apply update now? [y/N] " ans
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
	echo -e "${RED}No .deb on this release; cannot --apply automatically.${NC}" >&2
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
