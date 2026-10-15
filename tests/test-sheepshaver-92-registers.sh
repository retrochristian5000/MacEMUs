#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${CXX:=c++}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver92-regs.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
"$CXX" -std=c++11 -Wall -Wextra -Werror -I SheepShaver/src/kpx_cpu/src \
  SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-mmu.cpp \
  tests/test-sheepshaver-92-registers.cpp -o "$tmp/test"
"$tmp/test"
