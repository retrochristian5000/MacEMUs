#!/usr/bin/env python3
"""Structural regression for the PPC32 rfi decoder wiring.

Run: python3 SheepShaver/src/kpx_cpu/tests/test-ppc32-rfi-decode.py
This does NOT execute guest code or validate a Mac OS boot.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1] / "src" / "cpu" / "ppc"

def read(name):
    return (ROOT / name).read_text(encoding="utf-8")

def require(name, pattern, source):
    matches = re.findall(pattern, source, re.MULTILINE)
    assert len(matches) == 1, f"{name}: expected exactly one match, found {len(matches)}"

opcode = 0x4C000064
assert opcode >> 26 == 19
assert (opcode >> 1) & 0x3FF == 50
assert opcode & 1 == 0
require("rfi enum", r"\bPPC_I\(RFI\),", read("ppc-instructions.hpp"))
require("rfi decode", r'\{ "rfi",\s+EXECUTE_0\(rfi\),\s+PPC_I\(RFI\),\s+XL_form, 19, 50, CFLOW_JUMP', read("ppc-decode.cpp"))
require("rfi declaration", r"\bvoid execute_rfi\(uint32 opcode\);", read("ppc-cpu.hpp"))
execute = read("ppc-execute.cpp")
require("rfi definition", r"void powerpc_cpu::execute_rfi\(uint32 opcode\)", execute)
require("strict rfi encoding", r"opcode != 0x4c000064u", execute)
require("rfi state restoration", r"ppc32_regs_->rfi\(resume_pc\)", execute)
require("rfi control flow", r"pc\(\) = resume_pc;", execute)
translate = read("ppc-translate.cpp")
for mnemonic in ("MFSPR", "MTSPR"):
    require("JIT fallback for " + mnemonic,
            rf"case PPC_I\({mnemonic}\):[\s\S]*?if \(ppc32_regs_\)\s+goto do_generic;",
            translate)
print("PPC32 rfi decoder wiring: 9 structural checks passed")
