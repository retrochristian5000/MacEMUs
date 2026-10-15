// Inspect Apple ROM container identity and decode structure; no emulator.
#include "../SheepShaver/src/include/rom_image_reader.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#include <cstring>

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
    const bool ok = sheep_rom::decode(file.data(), file.size(),
                                     image.data(), image.size(), kind);
    const char *format = file.size() == sheep_rom::kRomSize ? "plain 4 MiB" :
        (file.size() >= 11 && !memcmp(file.data(), "<CHRP-BOOT>", 11)
         ? "CHRP compressed" : "unrecognized");
    std::printf("ROM file bytes: %lu\nContainer: %s\n",
                static_cast<unsigned long>(file.size()), format);
    if (!ok) {
        std::fprintf(stderr, "ROM validation FAILED: malformed/unsupported container or decoded identity\n");
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
    std::puts("ROM format and identity validated; guest Mac OS compatibility NOT established.");
    return 0;
}
