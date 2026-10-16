#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver92-regs.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

# Linkage regression: the opcode must not disappear from either the
# interpreter or the JIT while the standalone register tests keep passing.
cpu=SheepShaver/src/kpx_cpu/src/cpu/ppc
grep -F 'PPC_I(MTMSR),' "$cpu/ppc-instructions.hpp" >/dev/null
grep -F 'X_form, 31, 146, CFLOW_JUMP' "$cpu/ppc-decode.cpp" >/dev/null
grep -F 'void powerpc_cpu::execute_mtmsr(uint32 opcode)' "$cpu/ppc-execute.cpp" >/dev/null
grep -F 'case PPC_I(MTMSR):' "$cpu/ppc-translate.cpp" >/dev/null
grep -F 'opcode & 0x001ef801u' "$cpu/ppc-execute.cpp" >/dev/null
grep -F 'opcode & 0x00010000u' "$cpu/ppc-execute.cpp" >/dev/null

"$CXX" -std=c++11 -Wall -Wextra -Werror -I SheepShaver/src/kpx_cpu/src \
  SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-mmu.cpp \
  tests/test-sheepshaver-92-registers.cpp -o "$tmp/test"
"$tmp/test"
