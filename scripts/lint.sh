#!/usr/bin/env bash
# Run ShellCheck on the same paths as .github/workflows/ci.yml (options from .shellcheckrc); optionally tests and deb+lintian.
# Usage: from repo root — bash scripts/lint.sh [--tests|-t] [--deb] [--all]
#        VERSION=1.2.3  bash scripts/lint.sh --deb   (defaults to 0.0.0-ci for lintian)
set -euo pipefail

ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
cd "${ROOT}"

run_shellcheck() {
	command -v shellcheck >/dev/null 2>&1 || {
		echo "lint.sh: shellcheck not found (e.g. apt install shellcheck)" >&2
		return 127
	}
	shellcheck \
		bin/filesync \
		commands/*.sh \
		lib/*.sh \
		scripts/ci-test.sh \
		scripts/build-deb.sh \
		scripts/lint.sh \
		scripts/version-push.sh \
		tests/run-lib-tests.sh \
		tests/run-command-tests.sh \
		tests/harness-lib.sh \
		tests/harness-command.sh \
		tests/lib/*.sh \
		tests/commands/*.sh
}

run_tests() {
	bash "${ROOT}/scripts/ci-test.sh"
}

run_deb_lintian() {
	local ver="${VERSION:-0.0.0-ci}"
	local deb_version="${ver//[^a-zA-Z0-9.+~-]/}"
	command -v lintian >/dev/null 2>&1 || {
		echo "lint.sh: lintian not found (e.g. apt install lintian)" >&2
		return 127
	}
	command -v dpkg-deb >/dev/null 2>&1 || {
		echo "lint.sh: dpkg-deb not found (e.g. apt install dpkg-dev)" >&2
		return 127
	}
	VERSION="${ver}" bash "${ROOT}/scripts/build-deb.sh"
	lintian --fail-on warning "${ROOT}/filesync_${deb_version}_all.deb"
}

do_tests=0
do_deb=0
for _arg in "$@"; do
	case "${_arg}" in
		--tests|-t) do_tests=1 ;;
		--deb) do_deb=1 ;;
		--all) do_tests=1; do_deb=1 ;;
		-h|--help)
			printf '%s\n' \
				"Usage: bash scripts/lint.sh [--tests|-t] [--deb] [--all]" \
				"  (default)  ShellCheck only (same paths as GitHub Actions)." \
				"  --tests    Also run scripts/ci-test.sh" \
				"  --deb      Also build .deb and run lintian (VERSION default 0.0.0-ci)" \
				"  --all      ShellCheck, tests, and deb+lintian"
			exit 0
			;;
		*)
			echo "lint.sh: unknown option: ${_arg} (try --help)" >&2
			exit 2
			;;
	esac
done

run_shellcheck
printf '%s\n' 'lint.sh: ShellCheck OK'
if [[ "${do_tests}" -eq 1 ]]; then
	run_tests
fi
if [[ "${do_deb}" -eq 1 ]]; then
	run_deb_lintian
fi
