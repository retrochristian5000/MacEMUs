#!/bin/sh
# Safe offline staging tests: do not require Xcode or elevated privileges.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/macemu-install.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail() { printf 'install test: %s\n' "$*" >&2; exit 1; }
for name in BasiliskII SheepShaver; do
    mkdir -p "$tmp/build/$name/Release/$name.app/Contents/MacOS"
    printf '<plist/>\n' > "$tmp/build/$name/Release/$name.app/Contents/Info.plist"
    printf '%s\n' "$name" > "$tmp/build/$name/Release/$name.app/Contents/MacOS/$name"
done
make --no-print-directory install MACEMUS_PLATFORM=macos MACEMUS_HOMEBREW=off \
    MACEMUS_HOST_ARCH=arm64 XCODEBUILD=: BUILD_ROOT="$tmp/build" \
    PREFIX=/usr/local DESTDIR="$tmp/stage" >"$tmp/log" || fail 'staged install failed'
for name in BasiliskII SheepShaver; do
    [ -f "$tmp/stage/usr/local/Applications/$name.app/Contents/MacOS/$name" ] ||
        fail "missing installed $name"
done
if ./scripts/install-macos-app.sh "$tmp/stage" /usr/local \
    "$tmp/build/BasiliskII/Release/BasiliskII.app" >"$tmp/error" 2>&1; then
    fail 'existing app was overwritten'
fi
grep -F 'refusing to overwrite' "$tmp/error" >/dev/null || fail 'no overwrite guard'
make --no-print-directory install-basilisk MACEMUS_PLATFORM=macos MACEMUS_HOMEBREW=off \
    MACEMUS_HOST_ARCH=arm64 XCODEBUILD=: BUILD_ROOT="$tmp/build" \
    PREFIX="$tmp/prefix with spaces" DESTDIR= >"$tmp/log" || fail 'space path failed'
[ -f "$tmp/prefix with spaces/Applications/BasiliskII.app/Contents/Info.plist" ] ||
    fail 'path containing spaces lost'
for bad in relative ../invalid; do
    if ./scripts/install-macos-app.sh "$tmp/stage" "$bad" \
        "$tmp/build/BasiliskII/Release/BasiliskII.app" >"$tmp/error" 2>&1; then
        fail "accepted invalid PREFIX $bad"
    fi
done
if ./scripts/install-macos-app.sh relative /usr \
    "$tmp/build/BasiliskII/Release/BasiliskII.app" >"$tmp/error" 2>&1; then
    fail 'accepted relative DESTDIR'
fi
if ./scripts/install-macos-app.sh "$tmp/stage2" /usr \
    "$tmp/build/BasiliskII/Release/BasiliskII.app" "$tmp/missing/SheepShaver.app" \
    >"$tmp/error" 2>&1; then
    fail 'accepted missing second bundle'
fi
[ ! -e "$tmp/stage2/usr/Applications/BasiliskII.app" ] ||
    fail 'partially installed before preflight'
grep -F 'prefix="$(PREFIX)" DESTDIR="$(DESTDIR)" install' Makefile >/dev/null ||
    fail 'Unix install does not forward PREFIX/DESTDIR'
printf '%s\n' 'staged install tests: PASS'
