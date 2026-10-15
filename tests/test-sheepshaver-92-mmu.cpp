// ROM-free PowerPC32 BAT / HTAB / TLB regression fixtures.
// No Mac OS image, nanokernel, or platform initialization is required.
#include "cpu/ppc/ppc-mmu.hpp"
#include <cassert>
#include <cstdio>
#include <vector>
#include <stdint.h>

static void be32(std::vector<uint8_t>& ram, uint32_t offset, uint32_t val)
{
  assert(static_cast<size_t>(offset) + 4 <= ram.size());
  ram[offset] = static_cast<uint8_t>(val >> 24);
  ram[offset + 1] = static_cast<uint8_t>(val >> 16);
  ram[offset + 2] = static_cast<uint8_t>(val >> 8);
  ram[offset + 3] = static_cast<uint8_t>(val);
}

static uint32_t read_be32(const std::vector<uint8_t>& ram, uint32_t off)
{
  assert(static_cast<size_t>(off) + 4 <= ram.size());
  return (uint32_t(ram[off]) << 24) | (uint32_t(ram[off+1]) << 16) |
         (uint32_t(ram[off+2]) << 8) | uint32_t(ram[off+3]);
}

int main()
{
  ppc32_mmu m;
  const uint32_t ea = 0x20001234u;
  ppc32_xlate_result r = m.translate(ea, PPC32_XLATE_DR, 4);
  assert(r.ok && r.pa == ea && !r.via_bat);
  m.set_msr(ppc32_mmu::MSR_DR);
  r = m.translate(ea, PPC32_XLATE_DR, 4);
  assert(!r.ok && r.fault == PPC32_FAULT_NOTRANS);

  // Supervisor BAT, 128-KiB block: DR and IR are independent.
  m.set_dbat(0, 0x20000002u, 0x30000002u);
  r = m.translate(ea, PPC32_XLATE_DR, 4);
  assert(r.ok && r.via_bat && r.pa == 0x30001234u);
  r = m.translate(ea, PPC32_XLATE_IR, 4);
  assert(r.ok && !r.via_bat && r.pa == ea); // MSR[IR] is off.
  m.set_msr(ppc32_mmu::MSR_DR | ppc32_mmu::MSR_PR);
  r = m.translate(ea, PPC32_XLATE_DR, 4);
  assert(!r.ok && r.fault == PPC32_FAULT_NOTRANS); // supervisor BAT only.
  m.set_msr(ppc32_mmu::MSR_DR);
  m.set_dbat(0, 0x20000002u, 0x30000003u); // read-only BAT.
  r = m.translate(ea, PPC32_XLATE_DR, 4, true);
  assert(!r.ok && r.fault == PPC32_FAULT_PROT);
  m.set_dbat(0, 0, 0);

  // Synthetic 64-KiB HTAB at 0x10000, mapping EA page to PA 0x30000.
  std::vector<uint8_t> mem(0x60000u, 0);
  m.set_physical_memory(mem.data(), static_cast<uint32_t>(mem.size()));
  const uint32_t sdr1 = 0x00010000u, vsid = 0xabcdu;
  m.set_sdr1(sdr1);
  m.set_sr(2, vsid);
  const uint32_t hash = (vsid & 0x7ffffu) ^ ((ea >> 12) & 0xffffu);
  const uint32_t pteg = (sdr1 & 0xffff0000u) | ((hash * 64u) & 0xffffu);
  const uint32_t pte0 = 0x80000000u | (vsid << 7) | ((ea >> 22) & 0x3fu);
  be32(mem, pteg, pte0);
  be32(mem, pteg + 4u, 0x00030002u); // RPN + PP=2 (RW)
  r = m.translate(ea, PPC32_XLATE_DR, 4);
  assert(r.ok && !r.via_bat && r.pa == 0x00030234u);
  assert(read_be32(mem, pteg + 4u) & 0x100u); // PTE referenced bit.
  r = m.translate(ea, PPC32_XLATE_DR, 4, true);
  assert(r.ok && (read_be32(mem, pteg + 4u) & 0x80u)); // changed bit.

  // Invalidate stale cached translation after guest edits HTAB.
  be32(mem, pteg + 4u, 0x00040002u);
  r = m.translate(ea, PPC32_XLATE_DR, 4);
  assert(r.ok && r.pa == 0x00030234u); // cached old translation.
  m.tlbie(ea);
  r = m.translate(ea, PPC32_XLATE_DR, 4);
  assert(r.ok && r.pa == 0x00040234u);

  // Instruction fetch from non-executable segment must fault.
  m.set_sr(2, vsid | 0x10000000u);
  m.set_msr(ppc32_mmu::MSR_IR | ppc32_mmu::MSR_DR);
  r = m.translate(ea, PPC32_XLATE_IR, 4);
  assert(!r.ok && r.fault == PPC32_FAULT_NOEXEC);
  m.set_sr(2, vsid);
  r = m.translate(ea, PPC32_XLATE_IR, 4);
  assert(r.ok && r.pa == 0x00040234u);
  m.reset();
  r = m.translate(ea, PPC32_XLATE_IR, 4);
  assert(r.ok && r.pa == ea);
  std::puts("PowerPC32 experimental MMU: BAT / HTAB / TLB / faults PASS");
  return 0;
}
