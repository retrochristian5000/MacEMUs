#!/bin/sh
# ROM parsing coverage using synthetic, copyright-free test images.
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-rom-verify.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
"$CXX" -std=c++11 -O2 -Wall -Wextra -Werror \
    tests/test-sheepshaver-rom-verification.cpp -o "$tmp/test"
"$tmp/test"
