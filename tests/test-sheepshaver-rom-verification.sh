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
"$tmp/test" "$tmp/valid.rom" "$tmp/valid-chrp.rom" "$tmp/relocated.rom"
"$tmp/inspect" "$tmp/relocated.rom" > "$tmp/relocated-info"
grep -F "first +0x3106f8" "$tmp/relocated-info" >/dev/null
grep -F "Candidate PPC code at decoded-ROM +0x3106f8" "$tmp/relocated-info" >/dev/null
grep -F "4 words SheepShaver would overwrite: 354afffc 7d86502e 12345678 87654321" "$tmp/relocated-info" >/dev/null
grep -F "PVR opcode hits=1, matching companion cmpwi=1" "$tmp/relocated-info" >/dev/null
"$tmp/inspect" "$tmp/valid.rom" > "$tmp/info"
grep -F "Identity: NewWorld" "$tmp/info" >/dev/null
grep -F "Decoded ROM header: checksum-field=" "$tmp/info" >/dev/null
grep -F "version-field=" "$tmp/info" >/dev/null
grep -F "Nanokernel sr_init signature: MISSING" "$tmp/info" >/dev/null
"$tmp/inspect" "$tmp/valid-chrp.rom" > "$tmp/chrp-info"
grep -F "Container: CHRP compressed" "$tmp/chrp-info" >/dev/null
grep -F "CHRP declared payload: lzss offset=0x00000080" "$tmp/chrp-info" >/dev/null
grep -F "CHRP payload end:" "$tmp/chrp-info" >/dev/null
grep -F "CHRP payload / decoded ROM:" "$tmp/chrp-info" >/dev/null
grep -F "CHRP boot icon bitmap: tag at outer file" "$tmp/chrp-info" >/dev/null
grep -F "Nanokernel sr_init signature: MISSING" "$tmp/chrp-info" >/dev/null
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

# Fail-closed, transactional patching: incompatible ROMs must not be left
# partly rewritten after fault-trip inspection or an aborted boot attempt.
grep -F 'ROMPatchTransaction transaction;' "$patch" >/dev/null
grep -F 'if (!transaction.ready())' "$patch" >/dev/null
grep -F 'memcpy(saved_, ROMBaseHost, ROM_SIZE);' "$patch" >/dev/null
grep -F 'memcpy(ROMBaseHost, saved_, ROM_SIZE);' "$patch" >/dev/null
grep -F 'transaction.commit();' "$patch" >/dev/null

# Exhaustion and corrupted ROM-linked pointers must be bounded, without
# making an unsupported ROM silently appear supported.
grep -F 'num_sifters >= int(sizeof(sifter_list) / sizeof(sifter_list[0]))' "$patch" >/dev/null
grep -F 'visited < ROM_SIZE / 14' "$patch" >/dev/null
grep -F 'next > ROM_SIZE - 14' "$patch" >/dev/null
grep -F 'target < ROM_SIZE ? target : 0' "$patch" >/dev/null
grep -F 'rom_trap_has_room(' "$patch" >/dev/null
grep -F 'invalid A-trap %04x target/patch span' "$patch" >/dev/null

# Only the pattern-match functions are instrumented. There must be no
# silent failure exit left within PatchROM and its required subpatches.
awk '
    /^bool PatchROM\(void\)/ { scanning=1; next }
    /^void InstallDrivers\(void\)/ { scanning=0 }
    scanning && /return false;/ { failures++ }
    END { exit failures != 0 }
' "$patch"
printf '%s\n' 'SheepShaver ROM decoder and patch diagnostics: PASS'
