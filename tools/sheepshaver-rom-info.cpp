// Inspect Apple ROM container identity and decode structure; no emulator.
#include "../SheepShaver/src/include/rom_image_reader.h"
#include "../SheepShaver/src/include/rom_patch_probe.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#include <cstring>

// CHRP BOOT script tags are ASCII, outside the compressed PowerPC ROM.
// Case-insensitive and bounded to the first 128 KiB of the container.
static size_t chrp_tag_offset(const std::vector<uint8_t> &data, const char *tag)
{
    const size_t n = data.size() < 131072u ? data.size() : 131072u;
    const size_t len = std::strlen(tag);
    for (size_t off = 0; off + len <= n; ++off) {
        bool equal = true;
        for (size_t i = 0; i < len; ++i) {
            unsigned a = data[off + i], b = static_cast<unsigned char>(tag[i]);
            if (a >= 'a' && a <= 'z') a -= 'a' - 'A';
            if (b >= 'a' && b <= 'z') b -= 'a' - 'A';
            if (a != b) { equal = false; break; }
        }
        if (equal) return off;
    }
    return size_t(-1);
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        std::fprintf(stderr, "Usage: sheepshaver-rom-info <path-to-Mac-OS-ROM>\n");
        return 2;
    }
    FILE *f = std::fopen(argv[1], "rb");
    if (!f) {
        std::perror("Cannot open ROM");
        return 1;
    }
    if (std::fseek(f, 0, SEEK_END) != 0) {
        std::perror("Cannot seek ROM");
        std::fclose(f); return 1;
    }
    long n = std::ftell(f);
    if (n <= 0 || uint64_t(n) > sheep_rom::kMaxFileSize ||
        std::fseek(f, 0, SEEK_SET) != 0) {
        std::fprintf(stderr, "ROM file is empty, unreadable or exceeds 16 MiB\n");
        std::fclose(f); return 1;
    }
    std::vector<uint8_t> file(static_cast<size_t>(n));
    if (std::fread(file.data(), 1, file.size(), f) != file.size()) {
        std::perror("Could not read complete ROM");
        std::fclose(f); return 1;
    }
    std::fclose(f);
    std::vector<uint8_t> image(sheep_rom::kRomSize, 0);
    sheep_rom::Kind kind = sheep_rom::kInvalid;
    sheep_rom::DecodeStatus status = sheep_rom::kDecodeBadArguments;
    const bool ok = sheep_rom::decode(file.data(), file.size(),
                                     image.data(), image.size(), kind, &status);
    const bool is_chrp = file.size() >= 11 &&
        !memcmp(file.data(), "<CHRP-BOOT>", 11);
    const char *format = is_chrp ? "CHRP compressed" :
        (file.size() == sheep_rom::kRomSize ? "plain 4 MiB" : "unrecognized");
    std::printf("ROM file bytes: %lu\nContainer: %s\n",
                static_cast<unsigned long>(file.size()), format);
    if (is_chrp) {
        const size_t bitmap = chrp_tag_offset(file, "<BITMAP>");
        if (bitmap != size_t(-1))
            std::printf("CHRP boot icon bitmap: tag at outer file +0x%lx "
                        "(ASCII boot icon, not a PPC instruction)\n",
                        static_cast<unsigned long>(bitmap));
        else
            std::puts("CHRP boot icon bitmap: not found in first 128 KiB");

        // Report the bytes actually fed into the ROM decoder. A CHRP
        // container includes boot-script/icon data; its size is NOT the
        // compressed payload length or the decoded ROM capacity.
        uint32_t payload_offset = 0, payload_size = 0;
        const bool has_lzss =
            sheep_rom::chrp_constant(file.data(), file.size(),
                                     "constant lzss-offset", payload_offset) &&
            sheep_rom::chrp_constant(file.data(), file.size(),
                                     "constant lzss-size", payload_size);
        bool found = has_lzss;
        if (!found)
            found = sheep_rom::chrp_constant(file.data(), file.size(),
                                            "constant parcels-offset",
                                            payload_offset) &&
                    sheep_rom::chrp_constant(file.data(), file.size(),
                                            "constant parcels-size",
                                            payload_size);
        if (found) {
            std::printf("CHRP declared payload: %s offset=0x%08x size=%u bytes\n",
                        has_lzss ? "lzss" : "parcels",
                        unsigned(payload_offset), unsigned(payload_size));
            if (payload_size && payload_offset <= file.size() &&
                payload_size <= file.size() - payload_offset) {
                const size_t payload_end = size_t(payload_offset) + payload_size;
                std::printf("CHRP payload end: %lu; trailing container bytes: %lu\n",
                            static_cast<unsigned long>(payload_end),
                            static_cast<unsigned long>(file.size() - payload_end));
                std::printf("CHRP payload / decoded ROM: %.2f%% "
                            "(does not include outer boot script)\n",
                            double(payload_size) * 100.0 /
                            double(sheep_rom::kRomSize));
            } else {
                std::puts("CHRP payload bounds: invalid");
            }
        } else {
            std::puts("CHRP declared payload: no matching lzss/parcels metadata");
        }
    }
    if (!ok) {
        std::fprintf(stderr, "ROM validation FAILED: %s\n",
                     sheep_rom::decode_status_string(status));
        if (status == sheep_rom::kDecodeUnknownIdentity) {
            // These 16 decoded bytes are metadata, not executable code.
            std::fprintf(stderr, "Decoded identity at +0x30d064 (hex):");
            for (unsigned i = 0; i < 16; ++i)
                std::fprintf(stderr, " %02x", unsigned(image[0x30d064u + i]));
            std::fprintf(stderr, "\n");
        } else if (format[0] == 'C') {
            uint32_t off = 0, bytes = 0;
            bool found = sheep_rom::chrp_constant(
                file.data(), file.size(), "constant parcels-offset", off) &&
                sheep_rom::chrp_constant(
                    file.data(), file.size(), "constant parcels-size", bytes);
            if (!found)
                found = sheep_rom::chrp_constant(
                    file.data(), file.size(), "constant lzss-offset", off) &&
                        sheep_rom::chrp_constant(
                    file.data(), file.size(), "constant lzss-size", bytes);
            if (found)
                std::fprintf(stderr, "CHRP declared offset=0x%08x size=0x%08x\n",
                             unsigned(off), unsigned(bytes));
        }
        return 1;
    }
    std::printf("Decoded ROM: 4 MiB\nIdentity: %s\n",
                kind == sheep_rom::kNewWorld ? "NewWorld" : "OldWorld");
    // Status only: do not assert a particular NK entry shape for Old World.
    if (kind == sheep_rom::kNewWorld) {
        bool populated = false;
        for (size_t i = 0; i < 16; ++i)
            populated |= image[0x310000u + i] != 0;
        std::printf("New World nanokernel entry region: %s\n",
                    populated ? "nonzero" : "all zero (investigate)");
    }
    const sheep_rom::SRInitProbe probe =
        sheep_rom::probe_sr_init(image.data(), image.size());
    if (probe.expected_offset) {
        std::printf("Nanokernel sr_init signature: legacy window match +0x%lx\n",
                    static_cast<unsigned long>(probe.expected_offset));
    } else {
        std::printf("Nanokernel sr_init signature: MISSING from legacy "
                    "decoded-ROM window +0x3101B0..+0x3105B0\n");
        if (probe.elsewhere_count) {
            std::printf("  %u exact match(es) elsewhere in decoded "
                        "nanokernel, first +0x%lx (investigate; no auto-patch)\n",
                        probe.elsewhere_count,
                        static_cast<unsigned long>(probe.elsewhere_offset));
        } else {
            std::printf("  No exact match in +0x310000..+0x320000; "
                        "individual PPC word hits: first=%u, second=%u\n",
                        probe.first_word_count, probe.second_word_count);
        }
        std::printf("  Legacy start +0x3101B0 words: %08x %08x\n",
                    unsigned(probe.window_first_word),
                    unsigned(probe.window_second_word));
    }
    const size_t candidate = probe.expected_offset ? probe.expected_offset :
        (probe.elsewhere_count == 1 ? probe.elsewhere_offset : 0);
    if (candidate) {
        const sheep_rom::SRInitContext context =
            sheep_rom::probe_sr_init_context(image.data(), image.size(), candidate);
        if (context.valid) {
            std::printf("Candidate PPC code at decoded-ROM +0x%lx:\n",
                        static_cast<unsigned long>(candidate));
            std::printf("  Previous 4 words:");
            for (unsigned j = 0; j < 4; ++j)
                std::printf(" %08x", unsigned(context.before[j]));
            std::printf("\n  4 words SheepShaver would overwrite:");
            for (unsigned j = 0; j < 4; ++j)
                std::printf(" %08x", unsigned(context.overwrite[j]));
            std::printf("\n  Following 4 words:");
            for (unsigned j = 0; j < 4; ++j)
                std::printf(" %08x", unsigned(context.after[j]));
            std::printf("\n  PVR opcode hits=%u, matching companion cmpwi=%u",
                        context.pvr_matches, context.pvr_guarded_matches);
            if (context.pvr_guarded_first)
                std::printf(", first at +0x%lx",
                    static_cast<unsigned long>(context.pvr_guarded_first));
            std::printf("\n");
            if (probe.elsewhere_count)
                std::puts("  Relocation candidate is NOT automatically approved "
                          "for patching: surrounding control flow must be reviewed.");
        }
    }
    std::puts("ROM decoding verified; nanokernel signature status above is "
              "diagnostic only, not a compatibility guarantee.");
    return 0;
}
