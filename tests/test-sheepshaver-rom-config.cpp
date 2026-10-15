#include "../SheepShaver/src/include/startup_rom_config.h"
#include <cassert>
#include <cstdio>
int main() {
 using sheep_startup::rom_candidate_exists;
 assert(!rom_candidate_exists("nonexistent-rom"));
 assert(!rom_candidate_exists(""));
 FILE *f = std::fopen("ROM", "wb"); assert(f); std::fclose(f);
 assert(rom_candidate_exists(""));
 assert(!rom_candidate_exists("nonexistent-rom"));
 assert(std::remove("ROM") == 0);
 f = std::fopen("Mac OS ROM", "wb"); assert(f); std::fclose(f);
 assert(rom_candidate_exists(""));
 assert(rom_candidate_exists("nonexistent-rom"));
 assert(std::remove("Mac OS ROM") == 0);
 f = std::fopen("selected-rom", "wb"); assert(f); std::fclose(f);
 assert(rom_candidate_exists("selected-rom"));
 assert(!rom_candidate_exists(""));
 assert(std::remove("selected-rom") == 0);
 return 0;
}
