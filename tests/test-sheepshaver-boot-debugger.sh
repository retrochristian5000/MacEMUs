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

# A fatal opcode must not fall through or abort before the Cocoa inspection
# loop. Startup failures also need to be held before the normal Quit path.
header=SheepShaver/src/include/boot_debugger.h
grep -F 'int SheepShaverBootDebuggerTrip(' "$header" >/dev/null || fail 'fault trip C ABI missing'
grep -F 'boot_debug_trip("illegal instruction", pc(), opcode);' "$exec" >/dev/null || fail 'illegal opcode not trapped'
grep -F 'boot_debug_trip("privileged rfi", pc(), opcode);' "$exec" >/dev/null || fail 'rfi fault not trapped'
grep -F 'boot_debug_trip("privileged mtmsr", pc(), opcode);' "$exec" >/dev/null || fail 'mtmsr fault not trapped'
grep -F 'boot_debug_trip("privileged mfmsr", pc(), opcode);' "$exec" >/dev/null || fail 'mfmsr fault not trapped'
grep -F 'SheepShaverBootDebuggerTrip(startup_stage, 0, 0)' "$main" >/dev/null || fail 'startup failure not trapped'
grep -F '[NSApp runModalForWindow:boot_debug_window]' "$cocoa" >/dev/null || fail 'fault inspection loop missing'
grep -F 'boot_debug_tripped = YES;' "$cocoa" >/dev/null || fail 'no trip-state guard'
grep -F '[boot_debug_quit_button setHidden:NO]' "$cocoa" >/dev/null || fail 'explicit Quit action unavailable'
grep -F '[NSApp stopModalWithCode:NSModalResponseStop]' "$cocoa" >/dev/null || fail 'Quit cannot end trip'
grep -F 'return !boot_debug_tripped;' "$cocoa" >/dev/null || fail 'window can close during inspection'
grep -F 'SheepShaver-Fault-Trace.log' "$cocoa" >/dev/null || fail 'fault trace not persisted'

# Verify the C ABI boundary also compiles from plain C (not just ObjC++).
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheep-debugger.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat > "$tmp/header.c" <<'EOF'
#include "boot_debugger.h"
void probe(void) {
    SheepShaverBootDebuggerLog("check");
    SheepShaverBootDebuggerCPU(0, 0, 0);
    SheepShaverBootDebuggerPump();
    (void)SheepShaverBootDebuggerTrip("probe", 0, 0);
}
EOF
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -fsyntax-only \
    -I SheepShaver/src/include "$tmp/header.c"
printf '%s\n' 'SheepShaver default macOS boot-debugger wiring: PASS (structural)'
