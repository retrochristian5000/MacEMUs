#ifndef SHEEPSHAVER_STARTUP_ROM_CONFIG_H
#define SHEEPSHAVER_STARTUP_ROM_CONFIG_H
#include <unistd.h>
// Matches load_mac_rom(): a configured path or "ROM", then "Mac OS ROM".
namespace sheep_startup {
inline bool rom_readable(const char *path) {
  return path && path[0] && access(path, R_OK) == 0;
}
inline bool rom_candidate_exists(const char *configured) {
  const char *first = (configured && configured[0]) ? configured : "ROM";
  return rom_readable(first) || rom_readable("Mac OS ROM");
}
}
#endif
