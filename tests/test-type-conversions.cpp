#include "../BasiliskII/src/include/mac_clip_bounds.h"
#include <cassert>

int main()
{
    using namespace macemu_clip;
    assert(!scrap_length_fits(0));
    assert(scrap_length_fits(1));
    assert(scrap_length_fits(UINT32_MAX));
    if (sizeof(size_t) > sizeof(uint32_t))
        assert(!scrap_length_fits(static_cast<size_t>(UINT32_MAX) + 1));

    assert(styl_records_fit(2, 0));
    assert(!styl_records_fit(1, 0));
    assert(!styl_records_fit(21, 1));
    assert(styl_records_fit(22, 1));
    assert(!styl_records_fit(41, 2));
    assert(styl_records_fit(42, 2));
    assert(styl_records_fit(2 + 20 * 65535, 65535));

    assert(text_length_fits(INT32_MAX));
    if (sizeof(size_t) > sizeof(int32_t))
        assert(!text_length_fits(static_cast<size_t>(INT32_MAX) + 1));
    assert(text_range_fits(100, 0, 100));
    assert(text_range_fits(100, 50, 50));
    assert(!text_range_fits(100, -1, 3));
    assert(!text_range_fits(100, 80, 70));
    assert(!text_range_fits(100, 0, 101));

    assert(pict_dimensions_fit(1, 1));
    assert(pict_dimensions_fit(UINT16_MAX, UINT16_MAX));
    assert(!pict_dimensions_fit(0, 1));
    assert(!pict_dimensions_fit(-1, 1));
    assert(!pict_dimensions_fit(65536, 1));
    return 0;
}
