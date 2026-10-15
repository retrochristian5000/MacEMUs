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
# An explicit -f should replace, not merge, both existing .app directories.
for name in BasiliskII SheepShaver; do
    printf 'updated-%s\n' "$name" > "$tmp/build/$name/Release/$name.app/Contents/MacOS/$name"
    touch "$tmp/stage/usr/local/Applications/$name.app/Contents/obsolete"
done
make --no-print-directory install MACEMUS_PLATFORM=macos MACEMUS_HOMEBREW=off \
    MACEMUS_HOST_ARCH=arm64 XCODEBUILD=: BUILD_ROOT="$tmp/build" \
    PREFIX=/usr/local DESTDIR="$tmp/stage" INSTALL_FLAGS=-f >"$tmp/log" ||
    fail 'forced reinstall of both applications failed'
for name in BasiliskII SheepShaver; do
    [ "$(cat "$tmp/stage/usr/local/Applications/$name.app/Contents/MacOS/$name")" = "updated-$name" ] ||
        fail "force install retained old binary: $name"
    [ ! -e "$tmp/stage/usr/local/Applications/$name.app/Contents/obsolete" ] ||
        fail "force install merged stale resources: $name"
done
# Source validation still runs before any forced replacement.
if ./scripts/install-macos-app.sh -f "$tmp/stage" /usr/local \
    "$tmp/build/BasiliskII/Release/BasiliskII.app" \
    "$tmp/missing/Bad.app" >"$tmp/error" 2>&1; then
    fail 'force accepted a missing second application'
fi
[ -f "$tmp/stage/usr/local/Applications/BasiliskII.app/Contents/MacOS/BasiliskII" ] ||
    fail 'force removed a working app when a source was missing'
# Deliberately fail the second final rename to verify both old apps roll back.
mkdir -p "$tmp/mock"
cat > "$tmp/mock/mv" <<'MOCK'
#!/bin/sh
case "$1" in */new/SheepShaver.app) exit 21 ;; esac
exec /bin/mv "$@"
MOCK
chmod +x "$tmp/mock/mv"
if PATH="$tmp/mock:$PATH" ./scripts/install-macos-app.sh -f "$tmp/stage" /usr/local \
    "$tmp/build/BasiliskII/Release/BasiliskII.app" \
    "$tmp/build/SheepShaver/Release/SheepShaver.app" >"$tmp/error" 2>&1; then
    fail 'simulated failed rename returned success'
fi
for name in BasiliskII SheepShaver; do
    [ "$(cat "$tmp/stage/usr/local/Applications/$name.app/Contents/MacOS/$name")" = "updated-$name" ] ||
        fail "failed force install did not restore $name"
done
# Reject unsupported install options rather than interpolating them into shell.
if make -n --no-print-directory install MACEMUS_PLATFORM=macos \
    MACEMUS_HOMEBREW=off MACEMUS_HOST_ARCH=arm64 \
    INSTALL_FLAGS='--unexpected' >"$tmp/error" 2>&1; then
    fail 'unsupported install flags were silently accepted'
fi
grep -F 'INSTALL_FLAGS supports only -f' "$tmp/error" >/dev/null ||
    fail 'no invalid flag diagnostic'
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
