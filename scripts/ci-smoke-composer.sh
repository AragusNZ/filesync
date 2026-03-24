#!/usr/bin/env bash
# Install this package via a Composer path repository and run the binary.
set -euo pipefail
ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

cd "${TMP}"
composer init --no-interaction --name="test/filesync-smoke" --type=project
composer config repositories.filesync path "${ROOT}"
composer require 'aragusnz/filesync:@dev' --no-interaction
"${TMP}/vendor/bin/filesync" help | grep -q 'filesync'
