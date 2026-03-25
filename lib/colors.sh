#!/usr/bin/env bash
# ANSI colors for terminal output (source from commands / runtime).
# shellcheck disable=SC2034

# Use ANSI bytes (not the literal two-char sequence "\\033") so printf '%s' and echo without -e still colorize.
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
WHITE=$'\033[0;37m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
GRAY=$'\033[0;90m'
NC=$'\033[0m'
