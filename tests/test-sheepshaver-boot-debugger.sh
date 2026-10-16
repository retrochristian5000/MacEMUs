#!/bin/sh
# Structural smoke test: Cocoa boot-debugger wiring, no Xcode or ROM required.
set -eu
cd "$(dirname "$0")/.."
fail() { printf 'boot debugger: %s\n' "$*" >&2; exit 1; }

prefs=SheepShaver/src/prefs_items.cpp
main=SheepShaver/src/Unix/main_unix.cpp
cocoa=SheepShaver/src/MacOSX/prefs_macosx.mm
cpu=SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-cpu.cpp
exec=SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-execute.cpp
glue=SheepShaver/src/kpx_cpu/sheepshaver_glue.cpp
xcode=SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj/project.pbxproj

grep -F 'PrefsAddBool("bootdebugger", true)' "$prefs" >/dev/null || fail 'default must be enabled'
grep -F 'SheepShaverBootDebuggerOpen(PrefsFindBool("bootdebugger"))' "$main" >/dev/null || fail 'window startup hook missing'
grep -F 'SheepShaverBootDebuggerLog(dbg_line)' "$main" >/dev/null || fail 'startup stages missing'
grep -F 'SheepShaverBootDebuggerCPU(' "$cpu" >/dev/null || fail 'CPU samples missing'
grep -F 'SheepShaverBootDebuggerPump()' "$glue" >/dev/null || fail 'SDL event pump hook missing'
grep -F '[NSWindow alloc] initWithContentRect:' "$cocoa" >/dev/null || fail 'native debugger window missing'
grep -F '[boot_debug_text setEditable:NO]' "$cocoa" >/dev/null || fail 'diagnostic view must be read-only'
grep -F 'pthread_mutex_trylock' "$cocoa" >/dev/null || fail 'bounded nonblocking tracing missing'
grep -F '[FAULT]' "$exec" >/dev/null || fail 'PPC fault diagnostics missing'
grep -F '[mtmsr]' "$exec" >/dev/null || fail 'MSR transition tracing missing'
grep -F 'prefs_macosx.mm in Sources' "$xcode" >/dev/null || fail 'Cocoa file not in active target'
grep -F 'ppc-cpu.cpp in Sources' "$xcode" >/dev/null || fail 'CPU sampler not in active target'

# Verify the C ABI boundary also compiles from plain C (not just ObjC++).
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheep-debugger.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat > "$tmp/header.c" <<'EOF'
#include "boot_debugger.h"
void probe(void) {
    SheepShaverBootDebuggerLog("check");
    SheepShaverBootDebuggerCPU(0, 0, 0);
    SheepShaverBootDebuggerPump();
}
EOF
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsyntax-only \
    -I SheepShaver/src/include "$tmp/header.c"
printf '%s\n' 'SheepShaver default macOS boot-debugger wiring: PASS (structural)'
