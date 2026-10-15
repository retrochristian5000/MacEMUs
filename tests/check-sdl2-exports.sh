#!/bin/sh
# Native macOS SDL2 symbol/ABI and C-linker probe for sdl2-compat.
# No emulator is launched, and no Homebrew packages are modified.
set -eu

mode=${1:-}
libdir=${2:-}
headerdir=${3:-}
arch=${4:-}
extras=${5:-}

die() { printf 'SDL2 export check: %s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || die 'requires macOS with Apple linker tools'
[ "$mode" = dylib ] || die "selected SDL2 mode is '${mode:-none}', not dylib; this probe audits a real libSDL2.dylib only"
case "$arch" in
    arm64|x86_64) ;;
    *) die "unsupported architecture '$arch' (select arm64 or x86_64)" ;;
esac
[ -n "$libdir" ] || die 'no SDL2 library directory selected'
[ -n "$headerdir" ] || die 'no SDL2 header directory selected'
[ -f "$libdir/libSDL2.dylib" ] || die "missing $libdir/libSDL2.dylib"
[ -f "$headerdir/SDL.h" ] || die "missing $headerdir/SDL.h"
command -v xcrun >/dev/null 2>&1 || die 'Xcode command-line tools (xcrun) not installed'

lib=$libdir/libSDL2.dylib
tmp=$(mktemp -d "${TMPDIR:-/tmp}/macemu-sdl2-exports.XXXXXX") ||
    die 'cannot create a temporary directory'
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

printf 'SDL2 export check: library=%s arch=%s headers=%s\n' "$lib" "$arch" "$headerdir"
xcrun lipo -verify_arch "$arch" "$lib" ||
    die "selected library has no $arch Mach-O slice"
xcrun nm -arch "$arch" -gjU "$lib" >"$tmp/exports" ||
    die 'failed to inspect defined dynamic-library exports with nm'

# Extra names can be copied verbatim from "Undefined symbols ... _SDL_Foo".
# A leading underscore is tolerated; invalid names must fail explicitly.
missing=0
for original in SDL_Init SDL_Quit SDL_GetError SDL_OpenAudio SDL_MixAudio SDL_CreateRenderer $extras; do
    symbol=${original#_}
    case "$symbol" in
        SDL_*) ;;
        *) die "not an SDL export name: '$original'" ;;
    esac
    case "$symbol" in
        *[!a-zA-Z0-9_]*) die "invalid SDL export name: '$original'" ;;
    esac
    if grep -Fx "_$symbol" "$tmp/exports" >/dev/null; then
        printf '  exported: %s\n' "$symbol"
    else
        printf '  MISSING:  %s\n' "$symbol" >&2
        missing=1
    fi
done
[ "$missing" -eq 0 ] || die 'one or more SDL2 exports are missing; check library version and header/ABI'

printf '%s\n' 'Dylib dependency list (SDL3 may be opened dynamically):'
xcrun otool -L "$lib" || die 'cannot inspect linked dylibs'

# Resolve SDL symbols using the same -lSDL2 convention as the Xcode apps.
# SDL_MAIN_HANDLED avoids SDL_main macro rewriting and is irrelevant to the
# emulators own entrypoints. Compile/link this probe; do not execute it.
cat >"$tmp/probe.c" <<'EOF'
#define SDL_MAIN_HANDLED 1
#include <SDL.h>
#if SDL_MAJOR_VERSION != 2
#error This SDL2 linkage probe was given non-SDL2 headers
#endif
int main(void)
{
    SDL_AudioSpec spec = {0};
    Uint8 dst[1] = {0}, src[1] = {0};
    SDL_Init(0);
    SDL_OpenAudio(&spec, 0);
    SDL_MixAudio(dst, src, 1, SDL_MIX_MAXVOLUME);
    SDL_Renderer *renderer = SDL_CreateRenderer(0, -1, 0);
    SDL_Quit();
    return renderer == 0 && SDL_GetError() == 0 && dst[0] != 0;
}
EOF
xcrun --sdk macosx clang -arch "$arch" -std=c11 -Wall -Wextra \
    -I"$headerdir" "$tmp/probe.c" -L"$libdir" -lSDL2 -o "$tmp/probe" ||
    die 'SDL2 C link probe failed; check Xcode header/library alignment and undefined symbols'
printf '%s\n' 'SDL2 export and linker probe: PASS'
