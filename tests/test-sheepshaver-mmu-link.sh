#!/bin/sh
# Guard the PPC32 MMU definition and all active SheepShaver link paths.
# Does not require Xcode or start the emulator.
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"

fail() { printf 'SheepShaver MMU link: %s\n' "$*" >&2; exit 1; }
mmu=SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-mmu.cpp
test -f "$mmu" || fail 'MMU implementation is missing'

# The root macOS build selects Xcode8, not the legacy Xcode project.
grep -F 'xcodebuild' Makefile >/dev/null || fail 'no Xcode build entrypoint'
grep -F 'SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj -target SheepShaver' Makefile >/dev/null ||
    fail 'unexpected root macOS build target'

for proj in SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj/project.pbxproj \
            SheepShaver/src/MacOSX/SheepShaver.xcodeproj/project.pbxproj
do
    test -f "$proj" || fail "missing Xcode project: $proj"
    grep -F '/* ppc-mmu.cpp in Sources */ = {isa = PBXBuildFile;' "$proj" >/dev/null ||
        fail "missing ppc-mmu.cpp PBXBuildFile: $proj"
    grep -F '/* ppc-mmu.cpp */ = {isa = PBXFileReference;' "$proj" >/dev/null ||
        fail "missing ppc-mmu.cpp PBXFileReference: $proj"
    # 0846E497 is the kpx_cpu static library's Sources build phase in both projects.
    awk '
      /0846E49714B124DE00574779 \/\* Sources \*\// { in_cpu = 1; next }
      in_cpu && /ppc-mmu.cpp in Sources/ { found = 1 }
      in_cpu && /^[[:space:]]*};/ { exit }
      END { exit !found }
    ' "$proj" || fail "kpx_cpu does not compile ppc-mmu.cpp: $proj"
done

# Unix emulator and standalone PPC test both need a matching translation unit.
grep -F '../kpx_cpu/src/cpu/ppc/ppc-mmu.cpp' SheepShaver/src/Unix/configure.ac >/dev/null ||
    fail 'Unix CPUSRCS omits ppc-mmu.cpp'
grep -F 'cpu/ppc/ppc-mmu.cpp' SheepShaver/src/Unix/Makefile.in >/dev/null ||
    fail 'Unix CPU test sources omit ppc-mmu.cpp'

# Compile the *real* implementation, then link a separate TU that needs
# ppc32_mmu::reset and the global guest-MMU accessor. No stub symbols.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-mmu-link.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat > "$tmp/probe.cpp" <<'EOF'
#include "cpu/ppc/ppc-mmu.hpp"
int main() {
    ppc32_mmu mmu;
    mmu.reset();
    ppc32_guest_mmu().reset();
    return mmu.msr() != 0u;
}
EOF
"$CXX" -std=c++11 -Wall -Wextra -Werror -I SheepShaver/src/kpx_cpu/src \
    -c "$mmu" -o "$tmp/ppc-mmu.o"
"$CXX" -std=c++11 -Wall -Wextra -Werror -I SheepShaver/src/kpx_cpu/src \
    "$tmp/probe.cpp" "$tmp/ppc-mmu.o" -o "$tmp/probe"
"$tmp/probe"
printf '%s\n' 'SheepShaver PPC32 MMU source/link routing: PASS'
