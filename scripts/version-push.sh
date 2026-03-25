#!/usr/bin/env bash
# Bump share/VERSION (major / minor / patch), commit, tag v<version>, and push commit + tag.
set -euo pipefail

ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
cd "${ROOT}"

die() {
	echo "$(basename "$0"): $*" >&2
	exit 1
}

usage() {
	echo "usage: $(basename "$0") [--major | --minor]" >&2
	echo "  Reads the current version from share/VERSION, increments:" >&2
	echo "    --major  first number (X.0.0)" >&2
	echo "    --minor  second number (x.Y.0)" >&2
	echo "    (default) third number (x.y.Z)" >&2
	echo "  Then commits, creates annotated tag v<version>, and runs git push + git push origin v<version>." >&2
	exit 1
}

bump="patch"
while [[ "${#}" -gt 0 ]]; do
	case "${1}" in
		--major)
			[[ "${bump}" == patch ]] || die "use only one of --major, --minor"
			bump="major"
			shift
			;;
		--minor)
			[[ "${bump}" == patch ]] || die "use only one of --major, --minor"
			bump="minor"
			shift
			;;
		-h | --help)
			usage
			;;
		*)
			die "unknown option: ${1}"
			;;
	esac
done

[[ -r share/VERSION ]] || die "share/VERSION missing or unreadable"

read -r cur <share/VERSION || die "could not read share/VERSION"
cur="${cur//$'\r'/}"
[[ -n "${cur}" ]] || die "share/VERSION is empty"

core="${cur%%-*}"
core="${core%%+*}"
IFS=. read -r p1 p2 p3 _ <<<"${core}"

[[ -n "${p1}" && "${p1}" =~ ^[0-9]+$ ]] || die "cannot parse major from '${cur}'"
[[ -z "${p2}" || "${p2}" =~ ^[0-9]+$ ]] || die "cannot parse minor from '${cur}'"
[[ -z "${p3}" || "${p3}" =~ ^[0-9]+$ ]] || die "cannot parse patch from '${cur}'"

maj="${p1}"
min="${p2:-0}"
pat="${p3:-0}"

case "${bump}" in
	major)
		new_m=$((10#${maj} + 1))
		new_mm=0
		new_p=0
		;;
	minor)
		new_m=$((10#${maj}))
		new_mm=$((10#${min} + 1))
		new_p=0
		;;
	patch)
		new_m=$((10#${maj}))
		new_mm=$((10#${min}))
		new_p=$((10#${pat} + 1))
		;;
esac

ver="${new_m}.${new_mm}.${new_p}"

if [[ -n "$(git status --porcelain)" ]]; then
	die "working tree is not clean; commit or stash first"
fi

if git show-ref --verify --quiet "refs/tags/v${ver}"; then
	die "tag v${ver} already exists"
fi

current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || die "not a git repository"
[[ "${current_branch}" != HEAD ]] || die "detached HEAD; checkout a branch before running this script"

printf '%s\n' "${ver}" >share/VERSION
git add share/VERSION
git commit -m "Bump version to ${ver}"
git tag -a "v${ver}" -m "Release v${ver}"

git push
git push origin "v${ver}"

echo "Bumped to ${ver}; committed, tagged v${ver}, and pushed."
