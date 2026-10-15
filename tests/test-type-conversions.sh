#!/bin/sh
# Portable boundary tests (no Cocoa/Xcode required).
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/macemu-conversions.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
"$CXX" -std=c++11 -Wall -Wextra -Wconversion -Wsign-conversion -Werror \
    tests/test-type-conversions.cpp -o "$tmpdir/test-type-conversions"
"$tmpdir/test-type-conversions"
printf '%s\n' 'clipboard conversion boundary tests: PASS'
