#!/bin/sh
# Static regression checks of startup failure reporting and cleanup gating.
set -eu
cd "$(dirname "$0")/.."
file=SheepShaver/src/Unix/main_unix.cpp
grep -F "startup_checkpoint(\"SDL video/audio\")" "$file" >/dev/null
grep -F "startup_checkpoint(\"ROM file loading\")" "$file" >/dev/null
grep -F "startup_checkpoint(\"guest ROM execution\")" "$file" >/dev/null
grep -F 'startup_report("error", text)' "$file" >/dev/null
grep -F 'exit(startup_exit_status);' "$file" >/dev/null
grep -F 'if (startup_devices_ready)' "$file" >/dev/null
grep -F 'if (startup_system_ready)' "$file" >/dev/null
grep -F 'if (startup_preferences_ready)' "$file" >/dev/null
grep -F 'if (vm_init() < 0)' "$file" >/dev/null
grep -F 'SheepShaver.log' "$file" >/dev/null
printf '%s\n' 'SheepShaver app startup-reporting guards: PASS'
