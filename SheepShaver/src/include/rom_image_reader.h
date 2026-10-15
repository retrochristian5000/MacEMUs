#ifndef SHEEPSHAVER_ROM_IMAGE_READER_H
#define SHEEPSHAVER_ROM_IMAGE_READER_H

// Bounded ROM container parsing. Pure C++11: no Apple ROMs or SDL required.
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace sheep_rom {
enum { kRomSize = 4 * 1024 * 1024, kMaxFileSize = 16 * 1024 * 1024 };
enum Kind { kInvalid = 0, kOldWorld = 1, kNewWorld = 2 };

inline Kind identify(const uint8_t *rom, size_t bytes)
{
    if (!rom || bytes < 0x30d064u + 13u) return kInvalid;
    const uint8_t *p = rom + 0x30d064u;
    if (!memcmp(p, "NewWorld", 8)) return kNewWorld;
    const char *old[] = {"Boot TNT", "Boot Alchemy", "Boot Zanzibar",
                         "Boot Gazelle", "Boot Gossamer"};
    for (unsigned i = 0; i < sizeof(old) / sizeof(old[0]); ++i)
        if (!memcmp(p, old[i], strlen(old[i]))) return kOldWorld;
    return kInvalid;
}

inline bool be32(const uint8_t *bytes, size_t size, size_t offset, uint32_t &v)
{
    if (!bytes || offset > size || size - offset < 4) return false;
    const uint8_t *p = bytes + offset;
    v = (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) |
        (uint32_t(p[2]) << 8) | uint32_t(p[3]);
    return true;
}

inline int hex_digit(uint8_t c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

inline bool chrp_constant(const uint8_t *src, size_t n, const char *label, uint32_t &v)
{
    const size_t label_len = strlen(label);
    // Only inspect the text header, never search arbitrary compressed data.
    const size_t limit = n < 128u * 1024u ? n : 128u * 1024u;
    if (limit < label_len + 7) return false;
    for (size_t i = 7; i + label_len <= limit; ++i) {
        if (memcmp(src + i, label, label_len) != 0 || src[i - 1] != ' ') continue;
        uint32_t value = 0;
        bool valid = true;
        for (size_t j = i - 7; j < i - 1; ++j) {
            int d = hex_digit(src[j]);
            if (d < 0) { valid = false; break; }
            value = (value << 4) | uint32_t(d);
        }
        if (valid) { v = value; return true; }
    }
    return false;
}

inline bool lzss(const uint8_t *src, size_t n, uint8_t *dst, size_t cap)
{
    uint8_t dict[4096] = {};
    size_t si = 0, di = 0, out = 0;
    di = 0xfee;
    while (si < n && out < cap) {
        uint8_t flags = src[si++];
        for (unsigned bit = 0; bit < 8 && out < cap; ++bit) {
            if (flags & (1u << bit)) {
                if (si >= n) return false;
                uint8_t c = src[si++];
                dict[di] = c;
                di = (di + 1) & 0xfffu;
                dst[out++] = c;
            } else {
                if (n - si < 2) return false;
                unsigned ix = src[si++];
                unsigned count = src[si++];
                ix |= (count << 4) & 0xf00u;
                count = (count & 15u) + 3u;
                if (count > cap - out) return false;
                while (count--) {
                    uint8_t c = dict[ix & 0xfffu];
                    ++ix;
                    dict[di] = c;
                    di = (di + 1) & 0xfffu;
                    dst[out++] = c;
                }
            }
        }
    }
    return out == cap;
}

inline bool parcels(const uint8_t *src, size_t size, uint8_t *dst, size_t cap)
{
    uint32_t magic = 0;
    if (!be32(src, size, 0, magic) || magic != 0x7072636cu) return false;
    size_t pos = 0x14u;
    while (pos < size) {
        uint32_t next = 0, type = 0, lzoff = 0;
        if (!be32(src, size, pos, next) ||
            !be32(src, size, pos + 4, type) ||
            !be32(src, size, pos + 8, lzoff)) return false;
        size_t end = next ? size_t(next) : size;
        if (end > size || end <= pos || end - pos < 12) return false;
        if (type == 0x726f6d20u) {  // 'rom ' parcel
            if (lzoff < 12 || size_t(lzoff) >= end - pos) return false;
            return lzss(src + pos + lzoff, end - pos - lzoff, dst, cap);
        }
        if (!next) break;
        pos = end;
    }
    return false;  // No ROM parcel found.
}

inline bool decode(const uint8_t *src, size_t size, uint8_t *rom, size_t cap, Kind &kind)
{
    kind = kInvalid;
    if (!src || !rom || cap < kRomSize || size > kMaxFileSize) return false;
    if (size == kRomSize) {
        memcpy(rom, src, kRomSize);
    } else {
        if (size < 11 || memcmp(src, "<CHRP-BOOT>", 11) != 0) return false;
        uint32_t off = 0, bytes = 0;
        bool found = chrp_constant(src, size, "constant lzss-offset", off) &&
                     chrp_constant(src, size, "constant lzss-size", bytes);
        if (!found) {
            found = chrp_constant(src, size, "constant parcels-offset", off) &&
                    chrp_constant(src, size, "constant parcels-size", bytes);
        }
        if (!found || bytes == 0 || off > size || bytes > size - off) return false;
        uint32_t signature = 0;
        bool ok = be32(src, size, off, signature) &&
                  (signature == 0x7072636cu ?
                      parcels(src + off, bytes, rom, kRomSize) :
                      lzss(src + off, bytes, rom, kRomSize));
        if (!ok) return false;
    }
    kind = identify(rom, kRomSize);
    return kind != kInvalid;
}

} // namespace sheep_rom
#endif
