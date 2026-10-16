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
grep -F "decoded 4 MiB ROM has no recognized boot identity" "$tmp/info" >/dev/null

# A newer valid ROM must never be admitted by ignoring a missing patch.
patch=SheepShaver/src/rom_patches.cpp
grep -F 'rom_patch_failure(__func__, __LINE__)' "$patch" >/dev/null
grep -F 'last_start = ROM_SIZE - data_len' "$patch" >/dev/null
grep -F 'ROMPatchError()' SheepShaver/src/main.cpp >/dev/null
grep -F 'ROMDecodeError()' SheepShaver/src/Unix/main_unix.cpp >/dev/null
grep -F 'Reading ROM source:' SheepShaver/src/Unix/main_unix.cpp >/dev/null
# Only the pattern-match functions are instrumented. There must be no
# silent failure exit left within PatchROM and its required subpatches.
awk '
    /^bool PatchROM\(void\)/ { scanning=1; next }
    /^void InstallDrivers\(void\)/ { scanning=0 }
    scanning && /return false;/ { failures++ }
    END { exit failures != 0 }
' "$patch"
printf '%s\n' 'SheepShaver ROM decoder and patch diagnostics: PASS'
