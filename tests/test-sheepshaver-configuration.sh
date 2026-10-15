#!/bin/sh
# Test C++ ROM search, and ensure Cocoa configuration precedes SDL.
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-config.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
"$CXX" -std=c++11 -Wall -Wextra -Werror tests/test-sheepshaver-rom-config.cpp -o "$tmp/test"
(cd "$tmp" && ./test)
main=SheepShaver/src/Unix/main_unix.cpp
grep -F 'rom_candidate_exists(PrefsFindString("rom"))' "$main" >/dev/null
grep -F 'ShowSheepShaverSettings();' "$main" >/dev/null
grep -F -- '--settings' "$main" >/dev/null
grep -F '[NSApp runModalForWindow:window]' SheepShaver/src/MacOSX/prefs_macosx.mm >/dev/null
grep -F 'SDL_WasInit(SDL_INIT_VIDEO)' SheepShaver/src/MacOSX/Launcher/VMSettingsController.mm >/dev/null
grep -F 'sheepshaver-settings: sheepshaver' Makefile >/dev/null
printf '%s\n' 'SheepShaver ROM/configuration routing: PASS'
