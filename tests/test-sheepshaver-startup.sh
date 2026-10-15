#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-limits.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
"$CXX" -std=c++11 -Wall -Wextra -Wconversion -Wsign-conversion -Werror \
    tests/test-sheepshaver-startup.cpp -o "$tmp/check"
"$tmp/check"
printf '%s\n' 'SheepShaver startup boundaries: PASS'
