#!/bin/sh
# Inspect SDL2 linkage without invoking Xcode or installing dependencies.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/macemu-sdl2.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/brew/lib" "$tmp/opt/lib" "$tmp/brew/Frameworks"
touch "$tmp/brew/lib/libSDL2.dylib"
out=$(make -n --no-print-directory basilisk sheepshaver MACEMUS_PLATFORM=macos MACEMUS_HOST_ARCH=arm64 MACEMUS_BREW=/bin/false MACEMUS_BREW_PREFIX="$tmp/brew")
printf '%s\n' "$out" | grep -F "MACEMUS_SDL2_LINK_FLAGS=\"$tmp/brew/lib/libSDL2.dylib\"" >/dev/null
printf '%s\n' "$out" | grep -F "MACEMUS_SDL2_LIBRARY_DIR=\"$tmp/brew/lib\"" >/dev/null
rm "$tmp/brew/lib/libSDL2.dylib"
touch "$tmp/opt/lib/libSDL2.dylib"
out=$(make -n --no-print-directory basilisk MACEMUS_PLATFORM=macos MACEMUS_HOST_ARCH=arm64 MACEMUS_BREW=/bin/false MACEMUS_BREW_PREFIX="$tmp/brew" MACEMUS_SDL2_PREFIX="$tmp/opt")
printf '%s\n' "$out" | grep -F "MACEMUS_SDL2_LIBRARY_DIR=\"$tmp/opt/lib\"" >/dev/null
printf '%s\n' "$out" | grep -F "MACEMUS_SDL2_LINK_FLAGS=\"$tmp/opt/lib/libSDL2.dylib\"" >/dev/null
out=$(make -n --no-print-directory basilisk MACEMUS_PLATFORM=macos MACEMUS_SDL2_LINKAGE=framework MACEMUS_HOMEBREW=off)
printf '%s\n' "$out" | grep -F 'MACEMUS_SDL2_LINK_FLAGS="-framework SDL2"' >/dev/null
if make -n --no-print-directory basilisk MACEMUS_PLATFORM=macos MACEMUS_SDL2_LINKAGE=dylib MACEMUS_HOMEBREW=off >"$tmp/error" 2>&1; then
    echo 'Missing dylib was not rejected' >&2
    exit 1
fi
grep -F 'SDL2 shared library not found' "$tmp/error" >/dev/null
# Reject a nonexistent explicitly selected path in auto mode, rather than
# silently falling back to an unrelated framework.
if make -n --no-print-directory basilisk MACEMUS_PLATFORM=macos \
    MACEMUS_HOMEBREW=off MACEMUS_SDL2_LIBRARY_DIR="$tmp/missing" >"$tmp/error" 2>&1; then
    echo 'Bad explicit SDL2 directory was accepted' >&2
    exit 1
fi
grep -F 'SDL2 shared library not found at' "$tmp/error" >/dev/null
# The export probe must use the same make-selected library and header paths.
out=$(make -n --no-print-directory check-sdl2-exports \
    MACEMUS_PLATFORM=macos MACEMUS_HOST_ARCH=arm64 \
    MACEMUS_BREW=/bin/false MACEMUS_BREW_PREFIX="$tmp/brew" \
    MACEMUS_SDL2_PREFIX="$tmp/opt" \
    SDL2_EXPECT_EXPORTS='SDL_CreateThread')
printf '%s\n' "$out" | grep -F 'tests/check-sdl2-exports.sh' >/dev/null
printf '%s\n' "$out" | grep -F "$tmp/opt/lib" >/dev/null
printf '%s\n' "$out" | grep -F 'SDL_CreateThread' >/dev/null
printf '%s\n' 'SDL2 framework/shared-library selection: PASS'
