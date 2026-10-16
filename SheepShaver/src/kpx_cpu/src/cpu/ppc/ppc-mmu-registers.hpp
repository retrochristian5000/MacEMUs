/*
 * Experimental PPC32 MMU supervisor registers for SheepShaver.
 * SheepShaver (C) Christian Bauer and Marc Hellwig.
 * MacEMUs additions licensed GPL-2.0-or-later.
 * The register bridge can be attached to the opt-in PPC interpreter/JIT
 * paths. Guest memory and instruction-fetch translation are NOT yet wired.
 */
#ifndef SHEEPSHAVER_PPC32_REGISTERS_HPP
#define SHEEPSHAVER_PPC32_REGISTERS_HPP
#include "cpu/ppc/ppc-mmu.hpp"
#include <stdint.h>

class ppc32_registers {
public:
    enum { DSISR = 18, DAR = 19, SDR1 = 25, SRR0 = 26, SRR1 = 27,
        SPRG0 = 272, SPRG3 = 275, PVR = 287,
        IBAT0U = 528, IBAT3L = 535, DBAT0U = 536, DBAT3L = 543,
        DSISR_STORE = 0x02000000u };
    explicit ppc32_registers(ppc32_mmu &mmu, uint32_t pvr)
        : mmu_(mmu), pvr_(pvr) { reset(); }
    void reset() {
        mmu_.reset();
        dsisr_ = dar_ = srr0_ = srr1_ = 0;
        for (unsigned i = 0; i < 4; ++i) sprg_[i] = 0;
    }
    // MSR and SR are not numbered SPRs: keep separate operations.
    uint32_t msr() const { return mmu_.msr(); }
    void set_msr(uint32_t v) { mmu_.set_msr(v); }

    // PowerPC OEA mfmsr: a supervisor-only read of the *current* MSR.
    // Leave the destination untouched when a program exception is needed.
    // The CPU caller is responsible for delivering that exception.
    bool mfmsr(uint32_t &value) const {
        const uint32_t current_msr = mmu_.msr();
        if (current_msr & ppc32_mmu::MSR_PR)
            return false;
        value = current_msr;
        return true;
    }

    // PPC32 mtmsr: only supervisor code may write MSR.
    // L=1 modifies EE and RI only. L=0 updates writable MSR bits but
    // leaves ME (machine-check enable) and LE (endianness) unchanged.
    // Do not change any state on a privilege failure. The CPU caller
    // handles execution synchronization and guest exceptions.
    bool mtmsr(uint32_t value, bool limited) {
        const uint32_t old_msr = mmu_.msr();
        if (old_msr & ppc32_mmu::MSR_PR)
            return false;
        const uint32_t mask = limited
            ? uint32_t(ppc32_mmu::MSR_EE | ppc32_mmu::MSR_RI)
            : ~uint32_t(ppc32_mmu::MSR_ME | ppc32_mmu::MSR_LE);
        mmu_.set_msr((old_msr & ~mask) | (value & mask));
        return true;
    }
    bool read_sr(unsigned i, uint32_t &v) const {
        if (i >= 16) return false;
        v = mmu_.sr(i); return true;
    }
    bool write_sr(unsigned i, uint32_t v) {
        if (i >= 16) return false;
        if (mmu_.sr(i) != v) { mmu_.set_sr(i, v); mmu_.tlbia(); }
        return true;
    }
    static unsigned spr_from_opcode(uint32_t insn) {
        return ((insn >> 16) & 31u) | (((insn >> 11) & 31u) << 5);
    }
    bool read_spr(unsigned id, uint32_t &v) const {
        if (id >= IBAT0U && id <= DBAT3L) return read_bat(id, v);
        switch (id) {
        case DSISR: v = dsisr_; return true;
        case DAR:   v = dar_; return true;
        case SDR1:  v = mmu_.sdr1(); return true;
        case SRR0:  v = srr0_; return true;
        case SRR1:  v = srr1_; return true;
        case PVR:   v = pvr_; return true;
        default:
            if (id >= SPRG0 && id <= SPRG3) {
                v = sprg_[id-SPRG0]; return true;
            }
            return false;
        }
    }
    bool write_spr(unsigned id, uint32_t v) {
        if (id >= IBAT0U && id <= DBAT3L) return write_bat(id, v);
        switch (id) {
        case DSISR: dsisr_ = v; return true;
        case DAR: dar_ = v; return true;
        case SDR1: mmu_.set_sdr1(v); return true;
        case SRR0: srr0_ = v; return true;
        case SRR1: srr1_ = v; return true;
        default:
            if (id >= SPRG0 && id <= SPRG3) {
                sprg_[id-SPRG0] = v; return true;
            }
            return false; // PVR is read-only, unsupported SPRs do not lie.
        }
    }
    void tlbie(uint32_t ea) { mmu_.tlbie(ea); }
    void tlbia() { mmu_.tlbia(); }

    // 32-bit OEA: only MSR bits 0, 5-9, and 16-31 survive an
    // exception in SRR1. The other positions may hold exception data.
    // In particular, MSR[POW] must not be restored by rfi.
    enum { RFI_MSR_MASK = 0x87c0ffffu };

    // Return from interrupt in supervisor mode. No explicit operands:
    // SRR0 supplies the next PC and SRR1 supplies the restored MSR.
    // A false return signals a privileged-instruction exception to the
    // CPU layer; neither the PC nor MSR is modified on failure.
    // The CPU caller must end its basic block, clear any reservation,
    // and synchronize instruction fetching/translation after success.
    bool rfi(uint32_t &next_pc) {
        if (mmu_.msr() & ppc32_mmu::MSR_PR)
            return false;
        const uint32_t resume_pc = srr0_ & ~uint32_t(3);
        const uint32_t resume_msr = srr1_ & uint32_t(RFI_MSR_MASK);
        mmu_.set_msr(resume_msr);
        next_pc = resume_pc;
        return true;
    }

    // DSI only; ISI/other exception entries require CPU wiring.
    bool take_dsi(uint32_t pc, uint32_t ea, const ppc32_xlate_result &fault,
                  bool store, uint32_t &vector) {
        if (fault.ok || !fault.fault) return false;
        uint32_t old_msr = mmu_.msr();
        srr0_ = pc; srr1_ = old_msr; dar_ = ea;
        dsisr_ = fault.fault | (store ? uint32_t(DSISR_STORE) : 0u);
        vector = old_msr & ppc32_mmu::MSR_IP ? 0xfff00300u : 0x300u;
        mmu_.set_msr(old_msr & ~uint32_t(ppc32_mmu::MSR_EXC_CLEAR));
        return true;
    }
private:
    bool read_bat(unsigned id, uint32_t &v) const {
        const bool instruction = id < DBAT0U;
        const unsigned index = (id - (instruction ? IBAT0U : DBAT0U)) / 2;
        uint32_t upper=0, lower=0;
        if (instruction) mmu_.get_ibat(index,&upper,&lower);
        else mmu_.get_dbat(index,&upper,&lower);
        v = (id & 1u) ? lower : upper;
        return true;
    }
    bool write_bat(unsigned id, uint32_t v) {
        const bool instruction = id < DBAT0U;
        const unsigned index = (id - (instruction ? IBAT0U : DBAT0U)) / 2;
        uint32_t upper=0, lower=0;
        if (instruction) mmu_.get_ibat(index,&upper,&lower);
        else mmu_.get_dbat(index,&upper,&lower);
        if (id & 1u) lower=v; else upper=v;
        if (instruction) mmu_.set_ibat(index,upper,lower);
        else mmu_.set_dbat(index,upper,lower);
        mmu_.tlbia(); return true;
    }
    ppc32_mmu &mmu_;
    const uint32_t pvr_;
    uint32_t dsisr_,dar_,srr0_,srr1_,sprg_[4];
};
#endif
