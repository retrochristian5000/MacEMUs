#!/bin/sh
# Check optional Homebrew framework routing without requiring Xcode or brew.
set -eu
cd "$(dirname "$0")/.."
temp=$(mktemp -d "${TMPDIR:-/tmp}/macemu-frameworks.XXXXXX")
trap 'rm -rf "$temp"' EXIT HUP INT TERM
mkdir -p "$temp/brew/Frameworks"

# Simulate a detected common prefix with a real framework directory.
out=$(make --no-print-directory -n basilisk sheepshaver \
    MACEMUS_PLATFORM=macos MACEMUS_HOST_ARCH=arm64 \
    MACEMUS_BREW=/bin/false MACEMUS_BREW_PREFIX="$temp/brew") || exit 1
case "$out" in
    *"MACEMUS_FRAMEWORK_SEARCH_DIR=\"$temp/brew/Frameworks\""*) : ;;
    *) echo 'Homebrew framework directory missing from Xcode arguments' >&2; exit 1 ;;
esac

# A missing Frameworks directory must not produce an invalid Xcode path.
out=$(make --no-print-directory -n basilisk \
    MACEMUS_PLATFORM=macos MACEMUS_HOST_ARCH=arm64 \
    MACEMUS_BREW=/bin/false MACEMUS_BREW_PREFIX="$temp/absent") || exit 1
case "$out" in
    *MACEMUS_FRAMEWORK_SEARCH_DIR=*) echo 'Nonexistent framework directory propagated' >&2; exit 1 ;;
    *) : ;;
esac

# Disabled mode must not use any Homebrew paths.
out=$(make --no-print-directory -n basilisk \
    MACEMUS_PLATFORM=macos MACEMUS_HOMEBREW=off \
    MACEMUS_BREW_PREFIX="$temp/brew") || exit 1
case "$out" in
    *MACEMUS_FRAMEWORK_SEARCH_DIR=*) echo 'Homebrew off mode leaked framework directory' >&2; exit 1 ;;
    *) : ;;
esac
printf '%s\n' 'Homebrew framework path routing: PASS'
