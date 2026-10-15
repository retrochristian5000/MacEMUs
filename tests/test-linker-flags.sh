#!/bin/sh
# Smoke-test coordinator link-flag separation without running Xcode.
set -eu
cd "$(dirname "$0")/.."
fail() { printf '%s\n' "linker flags test: $*" >&2; exit 1; }
output=$(make --no-print-directory -n basilisk sheepshaver \
    MACEMUS_PLATFORM=macos MACEMUS_HOMEBREW=off \
    LDFLAGS='-L/test/target -Wl,-dead_strip' \
    HOST_LDFLAGS='-L/test/host' \
    CPPFLAGS='-DTEST_PREPROCESSOR=1') || fail "dry run failed"
case "$output" in
    *'MACEMUS_LDFLAGS="-L/test/target -Wl,-dead_strip"'*) : ;;
    *) fail "target LDFLAGS missing from Xcode invocations" ;;
esac
case "$output" in
    *'MACEMUS_HOST_LDFLAGS="-L/test/host"'*) : ;;
    *) fail "host linker flags missing from Xcode invocations" ;;
esac
case "$output" in
    *'MACEMUS_CPPFLAGS="-DTEST_PREPROCESSOR=1"'*) : ;;
    *) fail "CPPFLAGS regression in coordinator" ;;
esac
printf '%s\n' "$output" | grep -F 'MACEMUS_LDFLAGS=' >/dev/null ||
    fail "no Xcode target flags emitted"
printf '%s\n' "$output" | grep -F -- '-target BasiliskII' >/dev/null ||
    fail "Basilisk II target omitted"
printf '%s\n' "$output" | grep -F -- '-target SheepShaver' >/dev/null ||
    fail "SheepShaver target omitted"
info=$(make --no-print-directory linker-info MACEMUS_PLATFORM=macos \
    MACEMUS_HOMEBREW=off LDFLAGS='-L/test/target' HOST_LDFLAGS='-L/test/host') ||
    fail "linker-info failed"
printf '%s\n' "$info" | grep -F 'Target LDFLAGS: -L/test/target' >/dev/null ||
    fail "target diagnostic missing"
printf '%s\n' "$info" | grep -F 'Host LDFLAGS: -L/test/host' >/dev/null ||
    fail "host diagnostic missing"
printf '%s\n' 'linker flags smoke tests: PASS'
