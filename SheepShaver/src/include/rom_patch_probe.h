#ifndef SHEEPSHAVER_ROM_PATCH_PROBE_H
#define SHEEPSHAVER_ROM_PATCH_PROBE_H

// Read-only diagnostics for the legacy SheepShaver nanokernel boot signature.
// They NEVER authorize patching a new location: a byte hit alone cannot prove
// that surrounding control flow or overwritten instructions are compatible.
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace sheep_rom {

enum {
    kSRInitExpectedStart = 0x3101b0,
    kSRInitExpectedEnd   = 0x3105b0,
    kNanokernelStart     = 0x310000,
    kNanokernelEnd       = 0x320000
};

struct SRInitProbe {
    size_t expected_offset;       // 0 if no exact sequence in legacy window
    size_t elsewhere_offset;      // 0 if no exact sequence outside that window
    unsigned elsewhere_count;
    unsigned first_word_count;    // isolated first instruction within nanokernel
    unsigned second_word_count;   // isolated second instruction within nanokernel
    uint32_t window_first_word;   // two words from expected window, for comparison
    uint32_t window_second_word;
};

inline uint32_t probe_be32(const uint8_t *p) {
    return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) |
           (uint32_t(p[2]) << 8) | uint32_t(p[3]);
}

inline SRInitProbe probe_sr_init(const uint8_t *rom, size_t bytes)
{
    SRInitProbe probe = {};
    if (!rom || bytes < kNanokernelEnd ||
        bytes < kSRInitExpectedStart + 8)
        return probe;
    const uint32_t expected_first = 0x354afffcu;
    const uint32_t expected_second = 0x7d86502eu;
    probe.window_first_word = probe_be32(rom + kSRInitExpectedStart);
    probe.window_second_word = probe_be32(rom + kSRInitExpectedStart + 4);

    // PPC opcodes are 4-byte aligned. Scan the decoded ROM, not the outer
    // CHRP-BOOT text (which can contain hex-encoded ICON/BITMAP data).
    for (size_t off = kNanokernelStart; off + 8 <= kNanokernelEnd; off += 4) {
        const uint32_t w0 = probe_be32(rom + off);
        const uint32_t w1 = probe_be32(rom + off + 4);
        if (w0 == expected_first) ++probe.first_word_count;
        if (w0 == expected_second) ++probe.second_word_count;
        if (w0 != expected_first || w1 != expected_second) continue;
        if (off >= kSRInitExpectedStart && off < kSRInitExpectedEnd) {
            if (!probe.expected_offset) probe.expected_offset = off;
        } else {
            ++probe.elsewhere_count;
            if (!probe.elsewhere_offset) probe.elsewhere_offset = off;
        }
    }
    return probe;
}

} // namespace sheep_rom
#endif
