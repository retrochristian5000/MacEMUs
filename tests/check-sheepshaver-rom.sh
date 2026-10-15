#!/bin/sh
# Build a throwaway inspector, then examine one ROM without starting SDL.
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
rom=${SHEEPSHAVER_ROM:-Mac OS ROM}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-rom-info.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
"$CXX" -std=c++11 -O2 -Wall -Wextra -Werror \
    tools/sheepshaver-rom-info.cpp -o "$tmp/inspect"
"$tmp/inspect" "$rom"
