#!/bin/sh
# Test C++ ROM search, and ensure Cocoa configuration precedes SDL.
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-config.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
"$CXX" -std=c++11 -Wall -Wextra -Werror tests/test-sheepshaver-rom-config.cpp -o "$tmp/test"
(cd "$tmp" && ./test)
main=SheepShaver/src/Unix/main_unix.cpp
grep -F 'rom_candidate_exists(PrefsFindString("rom"))' "$main" >/dev/null
grep -F 'ShowSheepShaverSettings();' "$main" >/dev/null
grep -F -- '--settings' "$main" >/dev/null
grep -F '[NSApp runModalForWindow:window]' SheepShaver/src/MacOSX/prefs_macosx.mm >/dev/null
grep -F 'SDL_WasInit(SDL_INIT_VIDEO)' SheepShaver/src/MacOSX/Launcher/VMSettingsController.mm >/dev/null
grep -F 'sheepshaver-settings: sheepshaver' Makefile >/dev/null

# Default supervisor mode must be selected without a CLI flag, while explicit
# saved preferences and command-line arguments can still choose legacy mode.
prefs=SheepShaver/src/prefs_items.cpp
loader=SheepShaver/src/prefs.cpp
glue=SheepShaver/src/kpx_cpu/sheepshaver_glue.cpp
grep -F 'PrefsAddBool("ppc32supervisor", true);' "$prefs" >/dev/null
grep -F 'if (PrefsFindBool("ppc32supervisor")) {' "$glue" >/dev/null
grep -F 'attach_ppc32_registers(&supervisor_regs_);' "$glue" >/dev/null
grep -F 'Legacy PPC32 MSR stubs enabled (ppc32supervisor=false)' "$glue" >/dev/null
# Check override sequence in PrefsInit: defaults, saved prefs, CLI.
awk '
  /void PrefsInit\(/ { in_init=1 }
  in_init && /AddPrefsDefaults\(\)/ { if (stage != 0) exit 1; stage=1 }
  in_init && /LoadPrefs\(vmdir\)/ { if (stage != 1) exit 1; stage=2 }
  in_init && /Override prefs with command line options/ { if (stage != 2) exit 1; stage=3; exit }
  END { if (stage != 3) exit 1 }
' "$loader"
printf '%s\n' 'SheepShaver ROM/configuration routing and PPC32 default: PASS'
