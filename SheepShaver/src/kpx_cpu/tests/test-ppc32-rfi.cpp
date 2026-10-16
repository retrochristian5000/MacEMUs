/*
 * Standalone regression test for the experimental PPC32 MMU register bridge.
 * This does not test the live SheepShaver interpreter or JIT.
 *
 * From the repository root:
 * clang++ -std=c++11 -Wall -Wextra -Werror -I SheepShaver/src/kpx_cpu/src \
 *   SheepShaver/src/kpx_cpu/tests/test-ppc32-rfi.cpp \
 *   SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-mmu.cpp \
 *   -o /tmp/sheepshaver-test-rfi && /tmp/sheepshaver-test-rfi
 */
#include <stdint.h>
#include <stdio.h>
#include "cpu/ppc/ppc-mmu-registers.hpp"

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "%s:%d: failed: %s\\n", __FILE__, __LINE__, #condition); \
        return 1; \
    } \
} while (0)

int main()
{
    ppc32_mmu mmu;
    ppc32_registers regs(mmu, 0x00080000u);
    uint32_t value = 0;
    uint32_t next_pc = 0;

    // SRR1 exception reason bits must not be installed into MSR.
    CHECK(regs.write_spr(ppc32_registers::SRR0, 0x12345003u));
    CHECK(regs.write_spr(ppc32_registers::SRR1, 0xffffffffu));
    CHECK(regs.rfi(next_pc));
    CHECK(next_pc == 0x12345000u);
    CHECK(regs.msr() == 0x87c0ffffu);
    CHECK(regs.read_spr(ppc32_registers::SRR0, value));
    CHECK(value == 0x12345003u);
    CHECK(regs.read_spr(ppc32_registers::SRR1, value));
    CHECK(value == 0xffffffffu);

    // Problem-state rfi must report privilege failure without side effects.
    regs.set_msr(ppc32_mmu::MSR_PR | ppc32_mmu::MSR_IR);
    next_pc = 0xaabbccddu;
    CHECK(!regs.rfi(next_pc));
    CHECK(next_pc == 0xaabbccddu);
    CHECK(regs.msr() == (ppc32_mmu::MSR_PR | ppc32_mmu::MSR_IR));

    // Real MSR translation/interrupt flags are restored from SRR1.
    regs.set_msr(0u);
    CHECK(regs.write_spr(ppc32_registers::SRR0, 0x87654323u));
    CHECK(regs.write_spr(ppc32_registers::SRR1,
        ppc32_mmu::MSR_IR | ppc32_mmu::MSR_DR |
        ppc32_mmu::MSR_EE | ppc32_mmu::MSR_RI));
    CHECK(regs.rfi(next_pc));
    CHECK(next_pc == 0x87654320u);
    CHECK(regs.msr() == (ppc32_mmu::MSR_IR | ppc32_mmu::MSR_DR |
                         ppc32_mmu::MSR_EE | ppc32_mmu::MSR_RI));

    // Reset must clear the saved registers as well as the MMU state.
    regs.reset();
    CHECK(regs.msr() == 0u);
    CHECK(regs.read_spr(ppc32_registers::SRR0, value));
    CHECK(value == 0u);
    CHECK(regs.read_spr(ppc32_registers::SRR1, value));
    CHECK(value == 0u);
    puts("PPC32 rfi register bridge: OK");
    return 0;
}
