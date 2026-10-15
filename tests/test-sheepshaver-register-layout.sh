#!/bin/sh
# Regression: compile original CPU register types alongside MMU bridge.
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-register-layout.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
# The original Kheperix header is authoritative for the classic core.
legacy=SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-registers.hpp
grep -F 'union powerpc_vr' "$legacy" >/dev/null
grep -F 'struct powerpc_registers' "$legacy" >/dev/null
grep -F 'powerpc_vr vr[32]' "$legacy" >/dev/null
grep -F 'class powerpc_vscr' "$legacy" >/dev/null
grep -F 'class powerpc_cr_register' "$legacy" >/dev/null
grep -F 'class powerpc_xer_register' "$legacy" >/dev/null
grep -F '#include "cpu/ppc/ppc-registers.hpp"' SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-cpu.hpp >/dev/null
grep -F '#include "cpu/ppc/ppc-mmu-registers.hpp"' tests/test-sheepshaver-92-registers.cpp >/dev/null
"$CXX" -std=c++11 -Wall -Wextra -Werror \
  -I SheepShaver/src/kpx_cpu/src \
  tests/test-sheepshaver-register-layout.cpp \
  SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-mmu.cpp -o "$tmp/test"
"$tmp/test"
printf '%s\n' 'Kheperix PowerPC register layout / MMU isolation: PASS'
