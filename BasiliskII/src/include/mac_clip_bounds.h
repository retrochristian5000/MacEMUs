#ifndef MACEMU_CLIP_BOUNDS_H
#define MACEMU_CLIP_BOUNDS_H

#include <stddef.h>
#include <stdint.h>
#include <limits.h>

// The classic Mac clipboard and PICT formats have narrower limits than
// Cocoa's pointer-sized lengths and image dimensions.
namespace macemu_clip {

static inline bool scrap_length_fits(size_t bytes)
{
    return bytes != 0 && bytes <= UINT32_MAX;
}

static inline bool styl_records_fit(size_t bytes, uint16_t records)
{
    // Two-byte record count followed by 20-byte style entries.
    return bytes >= 2 && (bytes - 2) / 20 >= records;
}

static inline bool text_length_fits(size_t bytes)
{
    return bytes <= INT32_MAX;
}

static inline bool text_range_fits(size_t bytes, int32_t first, int32_t last)
{
    return text_length_fits(bytes) && first >= 0 && last >= first &&
           static_cast<size_t>(last) <= bytes;
}

static inline bool pict_dimensions_fit(long width, long height)
{
    return width > 0 && height > 0 && width <= UINT16_MAX &&
           height <= UINT16_MAX;
}

} // namespace macemu_clip

#endif // MACEMU_CLIP_BOUNDS_H
