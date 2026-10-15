#!/bin/sh
# Check SDL source files for calls requiring optional SDL libraries.
# SDL_MixAudio is core SDL2; SDL_mixer APIs instead begin with Mix_.
set -eu
cd "$(dirname "$0")/.."
files='BasiliskII/src/SDL/SDLMain.m
BasiliskII/src/SDL/audio_sdl.cpp
BasiliskII/src/SDL/audio_sdl3.cpp
BasiliskII/src/SDL/video_sdl.cpp
BasiliskII/src/SDL/video_sdl2.cpp
BasiliskII/src/SDL/video_sdl3.cpp
BasiliskII/src/SDL/prefs_sdl.cpp
BasiliskII/src/SDL/xpram_sdl.cpp'
# These are also the shared SDL implementations referenced by SheepShaver.
# Print matching code (rather than silently assuming any dependency exists).
found=0
for file in $files; do
    [ -f "$file" ] || { printf 'Missing source: %s\n' "$file" >&2; exit 1; }
    if grep -nE '(^|[^[:alnum:]_])(IMG_|Mix_|TTF_|SDLNet_)[[:alnum:]_]*[[:space:]]*\(' "$file"; then
        printf 'Additional SDL library calls found in %s\n' "$file"
        found=1
    fi
done
if [ "$found" -eq 0 ]; then
    printf '%s\n' 'SDL source audit: no calls to SDL2_image, SDL2_mixer, SDL2_ttf, or SDL2_net detected.'
    printf '%s\n' 'Core SDL2 uses SDL_* functions; its sdl2-compat runtime requires SDL3.'
else
    printf '%s\n' 'Review the matching symbols before adding their optional link libraries.'
fi
