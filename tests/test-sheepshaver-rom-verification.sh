#!/bin/sh
# ROM parsing coverage using synthetic, copyright-free test images.
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-rom-verify.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
"$CXX" -std=c++11 -O2 -Wall -Wextra -Werror \
    tests/test-sheepshaver-rom-verification.cpp -o "$tmp/test"
"$CXX" -std=c++11 -O2 -Wall -Wextra -Werror \
    tools/sheepshaver-rom-info.cpp -o "$tmp/inspect"
"$tmp/test" "$tmp/valid.rom"
"$tmp/inspect" "$tmp/valid.rom" > "$tmp/info"
grep -F "Identity: NewWorld" "$tmp/info" >/dev/null
# Reject a same-sized but identity-free image.
dd if=/dev/zero of="$tmp/bad.rom" bs=1048576 count=4 2>/dev/null
if "$tmp/inspect" "$tmp/bad.rom" >"$tmp/info" 2>&1; then
    printf "%s\n" "ROM inspector accepted an unknown identity" >&2
    exit 1
fi
