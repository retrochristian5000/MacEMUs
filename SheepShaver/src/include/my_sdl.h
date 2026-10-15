#include "config.h"

#if defined(USE_SDL3)
#include <SDL3/SDL.h>
#elif defined(USE_SDL2)
#include <SDL2/SDL.h>
#else
#include <SDL.h>
#endif

// The active Xcode emulator applications link to the SDL2 ABI. Reject a
// stray SDL 1.2 or SDL3 header before it can generate incompatible symbols.
#if defined(MACEMUS_EXPECT_SDL2) && SDL_MAJOR_VERSION != 2
#error MacEMUs expected SDL2 headers; inspect Homebrew and framework include paths
#endif
