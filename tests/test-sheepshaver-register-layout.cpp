/*
 * Compile the actual legacy ppc-registers.hpp and the new MMU register
 * bridge in one translation unit. Stubs ONLY supply unrelated bitfield
 * and spin-lock dependencies, avoiding host OS/SDL/Xcode requirements.
 */
#include <stdint.h>
#include <stddef.h>
#include <type_traits>
typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef int32_t int32;
typedef uint64_t uint64;

#define KPX_MAX_CPUS 1
// Bitfield implementation is tested elsewhere; this fixture checks types.
#define PPC_BITFIELDS_H
struct layout_field {
    static uint32 mask() { return 1u; }
    static uint32 extract(uint32) { return 0u; }
    static void insert(uint32 &v, uint32 x) { v = x; }
};
typedef layout_field standalone_CR_SO_field;
typedef layout_field standalone_CR_LT_field;
typedef layout_field standalone_CR_GT_field;
typedef layout_field standalone_CR_EQ_field;
typedef layout_field XER_SO_field;
typedef layout_field XER_OV_field;
typedef layout_field XER_CA_field;
typedef layout_field XER_COUNT_field;
typedef layout_field VSCR_NJ_field;
typedef layout_field VSCR_SAT_field;
// The actual spcflags class is platform-specific; not part of VR ABI.
#define SPCFLAGS_H
struct basic_spcflags { uint32 opaque; };

#include "cpu/ppc/ppc-registers.hpp"
#include "cpu/ppc/ppc-mmu-registers.hpp"

static_assert(sizeof(powerpc_vr) == 16, "PowerPC AltiVec register must be 128 bits");
static_assert(sizeof(powerpc_fpr) == 8, "PowerPC FPR must be 64 bits");
static_assert(sizeof(((powerpc_registers *)0)->vr) == 32 * 16,
              "Kheperix must preserve 32 vector registers");
static_assert(offsetof(powerpc_registers, vr) % alignof(powerpc_vr) == 0,
              "Vector-register bank must satisfy native union alignment");
static_assert(std::is_same<decltype(((powerpc_registers *)0)->vr[0]),
              powerpc_vr &>::value, "CPU VR bank type changed");

int main()
{
    powerpc_vr v = {};
    v.w[0] = 0xaabbccddu;
    if (v.w[0] != 0xaabbccddu)
        return 1;
    powerpc_registers regs = {};
    regs.vr[31].j[0] = 0x1122334455667788ull;
    if (regs.vr[31].j[0] != 0x1122334455667788ull)
        return 2;
    ppc32_mmu mmu;
    ppc32_registers supervisor(mmu, 0x000c0000u);
    uint32_t pvr = 0;
    if (!supervisor.read_spr(287, pvr) || pvr != 0x000c0000u)
        return 3;
    return 0;
}
