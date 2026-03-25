#!/usr/bin/env bash
# Build filesync_<version>_all.deb from the current tree (DESTDIR install under PREFIX=/usr).
set -euo pipefail
VERSION="${VERSION:?Set VERSION (e.g. 1.0.0 without leading v)}"
ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
PKGROOT="${WORKDIR}/pkg"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT}}"

make -C "${ROOT}" install DESTDIR="${PKGROOT}" PREFIX=/usr

gzip -9n "${PKGROOT}/usr/share/man/man1/filesync.1"

# Ensure installed CLI reports the same version as the .deb (e.g. CI tag).
install -d "${PKGROOT}/usr/lib/filesync/share"
printf '%s\n' "${VERSION}" >"${PKGROOT}/usr/lib/filesync/share/VERSION"

DOCDIR="${PKGROOT}/usr/share/doc/filesync"
mkdir -p "${DOCDIR}"
install -m644 "${ROOT}/debian/copyright" "${DOCDIR}/copyright"

install -d "${PKGROOT}/usr/share/lintian/overrides"
cat >"${WORKDIR}/filesync.lintian-overrides" <<'LINTIAN'
# Libraries under usr/lib/filesync/lib are dot-sourced by the dispatcher; they
# are intentionally not executable.
filesync: script-not-executable
LINTIAN
install -m644 "${WORKDIR}/filesync.lintian-overrides" \
	"${PKGROOT}/usr/share/lintian/overrides/filesync"

deb_version="${VERSION//[^a-zA-Z0-9.+~-]/}"

{
	printf 'filesync (%s) unstable; urgency=medium\n\n' "${deb_version}"
	printf '  * Packaged release.\n\n'
	printf ' -- AragusNZ <AragusNZ@users.noreply.github.com>  %s\n' "$(date -R)"
} >"${WORKDIR}/changelog.Debian"
gzip -9n -c "${WORKDIR}/changelog.Debian" >"${DOCDIR}/changelog.Debian.gz"
chmod 644 "${DOCDIR}/changelog.Debian.gz"

mkdir -p "${PKGROOT}/DEBIAN"

cat >"${PKGROOT}/DEBIAN/control" <<EOF
Package: filesync
Version: ${deb_version}
Section: utils
Priority: optional
Architecture: all
Maintainer: AragusNZ <AragusNZ@users.noreply.github.com>
Homepage: https://github.com/AragusNZ/filesync
Depends: jq, git
Description: map and sync files across git checkouts
 This package provides a Bash CLI that maps and synchronizes files across
 multiple git checkouts using a per-project .filesync/ directory (JSON
 configuration, repos, and file mappings). Typical commands are init, check,
 sync, list-files, list-repos, and helpers for repos and file rows.
EOF

mkdir -p "${OUTPUT_DIR}"
dpkg-deb --root-owner-group --build "${PKGROOT}" "${OUTPUT_DIR}/filesync_${deb_version}_all.deb"
