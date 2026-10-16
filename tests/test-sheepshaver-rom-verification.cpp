// No Apple ROM is bundled: synthetic Old World and CHRP New World fixtures.
#include "../SheepShaver/src/include/rom_image_reader.h"
#include "../SheepShaver/src/include/rom_patch_probe.h"
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
    const char boot_icon[] = "<ICON SIZE=1,1><BITMAP>ff</BITMAP></ICON>\n";
    assert(strlen(line) + strlen(boot_icon) < off - 11);
    memcpy(out.data() + 11, line, strlen(line));
    memcpy(out.data() + 11 + strlen(line), boot_icon, strlen(boot_icon));
    memcpy(out.data() + off, payload.data(), payload.size());
    return out;
}

// Compact, copyright-free LZSS fixture: zero runs refer to a dictionary
// slot that never holds the 8-byte NewWorld identity at ROM+0x30d064.
static std::vector<uint8_t> compact_fixture_lzss(const std::vector<uint8_t>& raw)
{
    const size_t marker = 0x30d064u;
    assert(raw.size() == sheep_rom::kRomSize);
    std::vector<uint8_t> out;
    size_t i = 0;
    while (i < raw.size()) {
        const size_t flags = out.size();
        out.push_back(0);
        for (unsigned token = 0; token < 8 && i < raw.size(); ++token) {
            size_t zeros = raw.size() - i < 18 ? raw.size() - i : 18;
            if (i < marker && zeros > marker - i) zeros = marker - i;
            const bool literal = (i >= marker && i < marker + 8) || zeros < 3;
            if (literal) {
                out[flags] |= uint8_t(1u << token);
                out.push_back(raw[i++]);
            } else {
                // Initial dictionary is zero, index 0x200 stays zero.
                out.push_back(0x00);
                out.push_back(uint8_t(0x20u | (zeros - 3u)));
                i += zeros;
            }
        }
    }
    return out;
}

int main(int argc, char **argv)
{
    std::vector<uint8_t> rom(sheep_rom::kRomSize, 0);
    std::vector<uint8_t> decoded(sheep_rom::kRomSize, 0);
    sheep_rom::Kind kind = sheep_rom::kInvalid;
    sheep_rom::DecodeStatus status = sheep_rom::kDecodeOK;
    assert(!sheep_rom::decode(rom.data(), rom.size(), decoded.data(), decoded.size(), kind, &status));
    assert(status == sheep_rom::kDecodeUnknownIdentity);
    memcpy(rom.data() + 0x30d064, "Boot Gossamer", 13);
    assert(sheep_rom::decode(rom.data(), rom.size(), decoded.data(), decoded.size(), kind));
    assert(kind == sheep_rom::kOldWorld);
    // Clear the longer OldWorld marker before testing the shorter NewWorld
    // signature, otherwise five stale suffix bytes corrupt the LZSS fixture.
    memset(rom.data() + 0x30d064, 0, 13);
    memcpy(rom.data() + 0x30d064, "NewWorld", 8);
    assert(sheep_rom::decode(rom.data(), rom.size(), decoded.data(), decoded.size(), kind));
    assert(kind == sheep_rom::kNewWorld);

    // sr_init must be an exact sequence in decoded PPC nanokernel code.
    // Relocation is reported, never automatically treated as patch-safe.
    std::vector<uint8_t> sr(rom);
    const uint8_t sr_bytes[8] = {0x35,0x4a,0xff,0xfc,0x7d,0x86,0x50,0x2e};
    sheep_rom::SRInitProbe probe = sheep_rom::probe_sr_init(sr.data(), sr.size());
    assert(!probe.expected_offset && !probe.elsewhere_offset);
    memcpy(sr.data() + 0x3101b0, sr_bytes, sizeof(sr_bytes));
    probe = sheep_rom::probe_sr_init(sr.data(), sr.size());
    assert(probe.expected_offset == 0x3101b0u && probe.elsewhere_count == 0);
    memset(sr.data() + 0x3101b0, 0, sizeof(sr_bytes));
    memcpy(sr.data() + 0x310700, sr_bytes, sizeof(sr_bytes));
    probe = sheep_rom::probe_sr_init(sr.data(), sr.size());
    assert(probe.expected_offset == 0 && probe.elsewhere_offset == 0x310700u);
    assert(probe.elsewhere_count == 1 && probe.first_word_count == 1);
    assert(probe.second_word_count == 1);
    // One surviving instruction is NOT a sufficient compatibility match.
    memset(sr.data() + 0x310704, 0, 4);
    probe = sheep_rom::probe_sr_init(sr.data(), sr.size());
    assert(!probe.expected_offset && !probe.elsewhere_offset);
    assert(probe.first_word_count == 1 && probe.second_word_count == 0);

    // Reproduce the reported 9.2.2 location exactly, without needing a
    // proprietary ROM. Verify the full set of words that would be replaced.
    memset(sr.data() + 0x310700, 0, sizeof(sr_bytes));
    const size_t reported = 0x3106f8u;
    memcpy(sr.data() + reported, sr_bytes, sizeof(sr_bytes));
    put_be32(sr, reported + 8, 0x12345678u);
    put_be32(sr, reported + 12, 0x87654321u);
    put_be32(sr, reported - 4, 0xaabbccddu);
    put_be32(sr, reported + 16, 0xdeadbeefu);
    const size_t pvr = 0x310740u;
    put_be32(sr, pvr, 0x7d9f42a6u);
    put_be32(sr, pvr + 24, 0x2c0c0001u);
    probe = sheep_rom::probe_sr_init(sr.data(), sr.size());
    assert(!probe.expected_offset && probe.elsewhere_offset == reported);
    assert(probe.elsewhere_count == 1);
    const sheep_rom::SRInitContext context =
        sheep_rom::probe_sr_init_context(sr.data(), sr.size(), reported);
    assert(context.valid && context.offset == reported);
    assert(context.before[3] == 0xaabbccddu);
    assert(context.overwrite[0] == 0x354afffcu);
    assert(context.overwrite[1] == 0x7d86502eu);
    assert(context.overwrite[2] == 0x12345678u);
    assert(context.overwrite[3] == 0x87654321u);
    assert(context.after[0] == 0xdeadbeefu);
    assert(context.pvr_guarded_matches == 1);
    assert(context.pvr_guarded_first == pvr);

    // A valid CHRP image padded to precisely 4 MiB must still be parsed
    // as CHRP, not copied as a raw ROM (regression for original dispatch).
    const std::vector<uint8_t> compact = compact_fixture_lzss(rom);
    std::vector<uint8_t> padded = wrap_chrp(compact, false);
    assert(padded.size() < sheep_rom::kRomSize);
    padded.resize(sheep_rom::kRomSize, 0);
    memset(decoded.data(), 0xcc, decoded.size());
    assert(sheep_rom::decode(padded.data(), padded.size(),
                             decoded.data(), decoded.size(), kind, &status));
    assert(status == sheep_rom::kDecodeOK && kind == sheep_rom::kNewWorld);
    assert(memcmp(decoded.data(), rom.data(), rom.size()) == 0);

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
    if (argc > 2) {
        FILE *f = std::fopen(argv[2], "wb");
        assert(f);
        assert(std::fwrite(chrp.data(), 1, chrp.size(), f) == chrp.size());
        assert(std::fclose(f) == 0);
    }
    assert(!sheep_rom::decode(chrp.data(), chrp.size() - 1,
                              decoded.data(), decoded.size(), kind, &status));
    assert(status == sheep_rom::kDecodeBadCHRPBounds);

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
    assert(!sheep_rom::decode(bad.data(), bad.size(), decoded.data(), decoded.size(), kind, &status));
    assert(status == sheep_rom::kDecodeTooLarge);
    std::puts("ROM format/identity: OldWorld + NewWorld CHRP lzss/prcl + padded CHRP PASS");
    return 0;
}
