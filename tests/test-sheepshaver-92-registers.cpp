// Offline register/MMU tests. No Apple firmware required.
#include "cpu/ppc/ppc-registers.hpp"
#include <cassert>
#include <cstdio>
#include <vector>
#include <stdint.h>
static void be32(std::vector<uint8_t> &v, unsigned p, uint32_t x) {
    assert(p+4<=v.size());
    for (int i=0;i<4;++i) v[p+i]=uint8_t(x>>(24-8*i));
}
int main() {
    ppc32_mmu mmu;
    ppc32_registers r(mmu, 0x000c0000u);
    uint32_t v=0;
    assert(r.read_spr(287,v)&&v==0x000c0000u);
    assert(!r.write_spr(287,9u));
    v=33; assert(!r.read_spr(1008,v)&&v==33);
    assert(!r.write_spr(1008,9u));
    assert(ppc32_registers::spr_from_opcode(((543u&31u)<<16)|((543u>>5)<<11))==543u);
    for(unsigned i=272;i<=275;++i) { assert(r.write_spr(i,i+1000)); assert(r.read_spr(i,v)&&v==i+1000); }
    for(unsigned i=18;i<=27;++i) if(i==18||i==19||i==25||i==26||i==27) {
        assert(r.write_spr(i,i+2000)); assert(r.read_spr(i,v)&&v==i+2000);
    }
    assert(r.write_sr(2,0xabcdu)); assert(r.read_sr(2,v)&&v==0xabcdu);
    assert(!r.write_sr(16,3)); v=9;assert(!r.read_sr(16,v)&&v==9);
    r.reset(); assert(r.read_spr(287,v)&&v==0x000c0000u);
    assert(r.read_spr(272,v)&&v==0);
    assert(r.read_spr(25,v)&&v==0);
    const uint32_t ea=0x20001234u;
    r.set_msr(ppc32_mmu::MSR_DR);
    ppc32_xlate_result x=mmu.translate(ea,PPC32_XLATE_DR,4);
    assert(!x.ok && x.fault==PPC32_FAULT_NOTRANS);
    assert(r.write_spr(536,0x20000002u)); assert(r.write_spr(537,0x30000002u));
    x=mmu.translate(ea,PPC32_XLATE_DR,4);
    assert(x.ok&&x.via_bat&&x.pa==0x30001234u);
    assert(r.write_spr(537,0x40000002u));
    x=mmu.translate(ea,PPC32_XLATE_DR,4); assert(x.ok&&x.pa==0x40001234u);
    assert(r.write_spr(536,0u)&&r.write_spr(537,0u));
    assert(r.write_spr(528,0x20000002u)&&r.write_spr(529,0x50000002u));
    x=mmu.translate(ea,PPC32_XLATE_IR,4); assert(x.ok&&x.pa==ea);
    r.set_msr(ppc32_mmu::MSR_DR|ppc32_mmu::MSR_IR);
    x=mmu.translate(ea,PPC32_XLATE_IR,4);assert(x.ok&&x.pa==0x50001234u);
    assert(r.write_spr(528,0u)&&r.write_spr(529,0u));
    std::vector<uint8_t> mem(0x60000u,0);
    mmu.set_physical_memory(mem.data(),uint32_t(mem.size()));
    assert(r.write_spr(25,0x10000u)&&r.write_sr(2,0xabcdu));
    const uint32_t hash=0xabcdu^((ea>>12)&0xffffu);
    const uint32_t pteg=0x10000u|((hash*64u)&0xffffu);
    be32(mem,pteg,0x80000000u|(0xabcdu<<7)|((ea>>22)&63u));
    be32(mem,pteg+4,0x30002u);
    x=mmu.translate(ea,PPC32_XLATE_DR,4);
    assert(x.ok&&x.pa==0x30234u);
    assert(r.write_sr(2,0x5678u));
    x=mmu.translate(ea,PPC32_XLATE_DR,4);
    assert(!x.ok&&x.fault==PPC32_FAULT_NOTRANS);
    r.set_msr(ppc32_mmu::MSR_DR|ppc32_mmu::MSR_IP|ppc32_mmu::MSR_EE);
    uint32_t vector=0;
    assert(r.take_dsi(0x2000u,ea,x,true,vector)&&vector==0xfff00300u);
    assert(r.read_spr(26,v)&&v==0x2000u);
    assert(r.read_spr(19,v)&&v==ea);
    assert(r.read_spr(18,v)&&v==(PPC32_FAULT_NOTRANS|0x02000000u));
    assert(r.read_spr(27,v)&&v==(ppc32_mmu::MSR_DR|ppc32_mmu::MSR_IP|ppc32_mmu::MSR_EE));
    assert(!(r.msr()&ppc32_mmu::MSR_DR)&&!(r.msr()&ppc32_mmu::MSR_EE));
    r.set_msr(0); x=mmu.translate(ea,PPC32_XLATE_DR,4);
    assert(x.ok&&!r.take_dsi(0,ea,x,false,vector));
    std::puts("PPC32 register/MMU contract: PASS");
    return 0;
}
