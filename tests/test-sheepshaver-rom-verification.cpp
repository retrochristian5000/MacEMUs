// No Apple ROM is bundled: synthetic Old World and CHRP New World fixtures.
#include "../SheepShaver/src/include/rom_image_reader.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

static void put_be32(std::vector<uint8_t> &buf, size_t i, uint32_t val)
{
    buf[i] = uint8_t(val >> 24); buf[i+1] = uint8_t(val >> 16);
    buf[i+2] = uint8_t(val >> 8); buf[i+3] = uint8_t(val);
}

static std::vector<uint8_t> literal_lzss(const std::vector<uint8_t>& raw)
{
    std::vector<uint8_t> out;
    for (size_t i = 0; i < raw.size(); i += 8) {
        out.push_back(0xff);
        size_t count = raw.size() - i < 8 ? raw.size() - i : 8;
        out.insert(out.end(), raw.begin()+i, raw.begin()+i+count);
    }
    return out;
}

static std::vector<uint8_t> wrap_chrp(const std::vector<uint8_t> &payload, bool parcel)
{
    assert(payload.size() <= 0xffffff);
    const unsigned off = 0x80u;
    std::vector<uint8_t> out(off + payload.size(), 0);
    memcpy(out.data(), "<CHRP-BOOT>", 11);
    char line[112];
    std::snprintf(line, sizeof(line), "%06X constant %s-offset\n%06X constant %s-size\n",
                  off, parcel ? "parcels" : "lzss",
                  unsigned(payload.size()), parcel ? "parcels" : "lzss");
    assert(strlen(line) < off - 11);
    memcpy(out.data() + 11, line, strlen(line));
    memcpy(out.data() + off, payload.data(), payload.size());
    return out;
}

int main(int argc, char **argv)
{
    std::vector<uint8_t> rom(sheep_rom::kRomSize, 0);
    std::vector<uint8_t> decoded(sheep_rom::kRomSize, 0);
    sheep_rom::Kind kind = sheep_rom::kInvalid;
    assert(!sheep_rom::decode(rom.data(), rom.size(), decoded.data(), decoded.size(), kind));
    memcpy(rom.data() + 0x30d064, "Boot Gossamer", 13);
    assert(sheep_rom::decode(rom.data(), rom.size(), decoded.data(), decoded.size(), kind));
    assert(kind == sheep_rom::kOldWorld);
    memcpy(rom.data() + 0x30d064, "NewWorld", 8);
    assert(sheep_rom::decode(rom.data(), rom.size(), decoded.data(), decoded.size(), kind));
    assert(kind == sheep_rom::kNewWorld);
    if (argc > 1) {
        FILE *f = std::fopen(argv[1], "wb");
        assert(f);
        assert(std::fwrite(rom.data(), 1, rom.size(), f) == rom.size());
        assert(std::fclose(f) == 0);
    }
    std::vector<uint8_t> lz = literal_lzss(rom);
    assert(lz.size() > sheep_rom::kRomSize);  // Actual format-limit regression.
    std::vector<uint8_t> chrp = wrap_chrp(lz, false);
    assert(sheep_rom::decode(chrp.data(), chrp.size(), decoded.data(), decoded.size(), kind));
    assert(kind == sheep_rom::kNewWorld);
    assert(!sheep_rom::decode(chrp.data(), chrp.size() - 1, decoded.data(), decoded.size(), kind));

    // 'prcl' with a final 'rom ' parcel, including the last-entry sentinel.
    std::vector<uint8_t> parcel(0x20 + lz.size(), 0);
    put_be32(parcel, 0, 0x7072636cu);
    put_be32(parcel, 0x14, 0);  // last parcel => end of input
    put_be32(parcel, 0x18, 0x726f6d20u);
    put_be32(parcel, 0x1c, 12);
    memcpy(parcel.data()+0x20, lz.data(), lz.size());
    std::vector<uint8_t> pc = wrap_chrp(parcel, true);
    assert(sheep_rom::decode(pc.data(), pc.size(), decoded.data(), decoded.size(), kind));
    assert(kind == sheep_rom::kNewWorld);
    put_be32(pc, 0x80 + 0x1c, 0xffffffffu);
    assert(!sheep_rom::decode(pc.data(), pc.size(), decoded.data(), decoded.size(), kind));

    std::vector<uint8_t> bad = chrp;
    memcpy(bad.data()+11, "FFFFFF", 6);  // offset out of bounds
    assert(!sheep_rom::decode(bad.data(), bad.size(), decoded.data(), decoded.size(), kind));
    bad = chrp;
    bad.resize(sheep_rom::kMaxFileSize+1);
    assert(!sheep_rom::decode(bad.data(), bad.size(), decoded.data(), decoded.size(), kind));
    std::puts("ROM format/identity: OldWorld + NewWorld CHRP lzss/prcl PASS");
    return 0;
}
