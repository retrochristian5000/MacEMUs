#include "../SheepShaver/src/include/startup_limits.h"
#include <cassert>
#include <stdint.h>
int main() {
    uint32_t bytes=0; bool small=false;
    using namespace sheep_startup;
    assert(!normalize_ram(-1,bytes,small));
    assert(normalize_ram(0,bytes,small) && small && bytes==16u*1024u*1024u);
    assert(normalize_ram(16,bytes,small) && !small && bytes==16u*1024u*1024u);
    assert(normalize_ram(64,bytes,small) && bytes==64u*1024u*1024u);
    assert(normalize_ram(1000,bytes,small) && bytes==1000u*1024u*1024u);
    assert(normalize_ram(1001,bytes,small) && small);
    assert(normalize_ram(INT32_MAX,bytes,small) && bytes==INT32_MAX);
    assert(!rom_payload_fits(3,0,4));
    assert(rom_payload_fits(16,12,4));
    assert(!rom_payload_fits(16,13,4));
    assert(!rom_payload_fits(16,0,3));
    assert(!rom_payload_fits(16,UINT32_MAX,10));
    assert(!rom_payload_fits(UINT32_MAX,UINT32_MAX-2,10));
    return 0;
}
