#ifndef SHEEPSHAVER_STARTUP_LIMITS_H
#define SHEEPSHAVER_STARTUP_LIMITS_H
#include <stdint.h>

// Portable input guards: the guest's memory layout uses 32-bit addresses.
namespace sheep_startup {
inline bool normalize_ram(int32_t preference, uint32_t &bytes, bool &small)
{
    if (preference < 0) return false;
    // Preserve the existing convention: 0..1000 denotes MiB.
    uint64_t amount = preference <= 1000 ?
        static_cast<uint64_t>(preference) * 1024u * 1024u :
        static_cast<uint64_t>(preference);
    const uint32_t minimum = 16u * 1024u * 1024u;
    small = amount < minimum;
    if (small) amount = minimum;
    if (amount > UINT32_MAX) return false;
    bytes = static_cast<uint32_t>(amount);
    return true;
}
inline bool rom_payload_fits(uint32_t available, uint32_t offset, uint32_t length)
{
    return length >= 4 && offset <= available && length <= available - offset;
}
} // namespace sheep_startup
#endif
