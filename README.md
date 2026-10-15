# MacEMUs

MacEMUs collects Basilisk II and SheepShaver in one source tree, with shared
`cxmon` sources. The root Makefile coordinates the two emulators without
replacing their existing platform build systems.

## Build either emulator or both

From the repository root:

```sh
make help
make basilisk          # Basilisk II only
make sheepshaver       # SheepShaver only
make                   # both (same as make all)
make clean-basilisk    # clean only Basilisk II
make clean-sheepshaver # clean only SheepShaver
make clean             # clean both
```

The active Xcode projects target macOS 12.0 or later, matching the
supported deployment range of Xcode 27. The Xcode 8 name of SheepShaver's
project file is historical; it is the active build project. The older
`SheepShaver.xcodeproj` remains as a legacy reference, not as the default
backend. Both app builds use explicit Xcode targets. The helper phases use
Xcode's macOS Clang toolchain with the selected architectures.

The deployment target can be overridden explicitly for an older installed
Xcode with `XCODE_ARGS='MACOSX_DEPLOYMENT_TARGET=11.0'`, provided that
version of Xcode supports the chosen target.

For Apple Silicon, Basilisk II's arm64 CPU uses GMP and MPFR. Xcode
searches the selected common Homebrew prefix's `include` and `lib`
directories first, then the individual formula locations if necessary.
On Intel, the common library path defaults to `/usr/local/lib`.
An alternate prefix can be selected using `MACEMUS_BREW_PREFIX` or
`MACEMUS_ARM64_PREFIX`/`MACEMUS_X86_64_PREFIX` in `XCODE_ARGS`.
Always verify that the library binaries contain the required architecture.

The Xcode CPU-generator helpers run on the *build host* (arm64 on a native
Apple Silicon shell, or x86_64 on an Intel shell). Do not propagate a global
`ARCHS=arm64` override into all nested Xcode targets: Basilisk II has
separate x86_64 and arm64 CPU-library dependencies. Leave Xcode's standard
architecture resolution intact until we separately redesign that dependency
graph.

The default build backend is selected by host: Xcode on macOS, the existing
Autotools/Make files in `src/Unix` on Unix-like hosts, and `src/Windows` on
MinGW/MSYS. To select explicitly, set `MACEMUS_PLATFORM=macos`, `unix`, or
`mingw`. Dependencies and host restrictions below still apply.

On macOS, builds go to separate `build/BasiliskII` and `build/SheepShaver`
directories. For example:

```sh
make basilisk CONFIGURATION=Debug
make all                        # common Homebrew prefix auto-detected
```

`BUILD_ROOT` changes the macOS output root. On Unix and MinGW, each emulator
uses its own existing build directory; `CONFIGURE_ARGS` is passed to
`autogen.sh` **only when no configured Makefile exists**. Subsequent calls
reuse the existing configuration rather than overwriting it.

SheepShaver's older MinGW build may need source links set up first. If the
build reports that they are missing, review the existing `SheepShaver/Makefile`
`links` recipe before running `make -C SheepShaver links`; it can rewrite
existing links/files. This preparation is intentionally not automatic.

The `cxmon` support tool retains its own build process and is not a third
emulator target.

### Homebrew discovery (macOS)

At startup, `make` discovers the Homebrew installation **once** using
`brew --prefix` and uses its common `bin`, `include`, and `lib`
directories:

- `bin` is added to `PATH` for Xcode build commands only.
- `include` and `lib` are passed to Basilisk II's Xcode
  architecture-specific header and library searches.
- GMP/MPFR formula prefixes are queried only if their header or library
  is absent from the shared directories. No `brew link --force`.

The default shared prefix is usually `/opt/homebrew` on Apple Silicon
and `/usr/local` on Intel. `make homebrew-info` shows the common paths
and any formula-specific fallbacks. Without Homebrew, the earlier Xcode
fallback paths remain usable.

```sh
make homebrew-info                  # inspect Homebrew and detected formulae
make basilisk                      # auto-discover libraries (if installed)
make all                           # both emulators
make basilisk MACEMUS_HOMEBREW=off  # disable discovery
make basilisk MACEMUS_HOMEBREW=required # error if Homebrew is missing
make basilisk MACEMUS_BREW=/custom/bin/brew
make basilisk MACEMUS_BREW_PREFIX=/custom/prefix
```

`XCODE_ARGS` comes last, so an explicit per-library override such as
`XCODE_ARGS='MACEMUS_MPFR_PREFIX=/custom/mpfr'` takes priority.
Direct Xcode builds retain their project-defined fallback prefixes.
The shell architecture and formula binary architectures must match; an Intel
Homebrew installation under Rosetta is **not** automatically used for arm64
linking.

**SDL2 header selection:** Homebrew's `sdl2-compat` runs the
SDL2-compatible API on SDL3 internally. Source built against that layer
still uses SDL2 declarations, not SDL3 headers.

```text
<prefix>/include/SDL2/SDL.h
-I<prefix>/include         # for #include <SDL2/SDL.h>
-I<prefix>/include/SDL2    # for #include <SDL.h>
```

The root Makefile checks the common prefix for the SDL2 header, then
passes both include directories to the active Xcode projects. If that
header is absent, an installed formula prefix can serve as fallback.
Use `MACEMUS_SDL2_INCLUDE_PREFIX=/alternate/prefix` to choose another
common prefix or `MACEMUS_SDL2_PREFIX` for a formula-specific fallback.
If neither header location is present, the original SDL2.framework
header setting is retained.

MacEMUs already contains native SDL3-specific code, but its current
Xcode targets compile SDL2-specific components. Its `my_sdl.h` uses
`<SDL2/SDL.h>` for `USE_SDL2`, `<SDL3/SDL.h>` for `USE_SDL3`,
and `<SDL.h>` otherwise. These are distinct compile modes.

**SDL2 limitation:** Both current Xcode projects still refer to
`/Library/Frameworks/SDL2.framework`. `make homebrew-info` reports a
Homebrew SDL2 formula if installed, but the Homebrew `libSDL2.dylib` cannot
satisfy those existing framework references. SDL2 library-style linking and
app bundling require a separate Xcode integration change; no filesystem
symlinks or forced Homebrew links are created here.

### CPPFLAGS: preprocessor and host-tool isolation

Use `CPPFLAGS` for preprocessing only (such as `-I`, `-D`, and `-U`).
Do **not** put linker options (`-L`, `-l`, `-framework`) or CPU-selection
flags (`-arch`) here. Homebrew's automatically detected headers already
arrive through the existing Xcode `HEADER_SEARCH_PATHS`; generic CPPFLAGS
remain an additional user-controlled layer.

```sh
make cppflags-info CPPFLAGS='-DMACEMUS_TRACE=1 -I/custom/include'
make basilisk CPPFLAGS='-DMACEMUS_TRACE=1 -I/custom/include'
make sheepshaver CPPFLAGS='-DMACEMUS_TRACE=1'
make basilisk HOST_CPPFLAGS='-DHOST_GENERATOR_TRACE=1'
```

On macOS, the root Makefile passes target `CPPFLAGS` to the
`MACEMUS_CPPFLAGS` Xcode build setting, which the active app/CPU targets
use for both C/Objective-C and C++/Objective-C++ compilation. It
**retains** Basilisk II's `-fwrapv`, SheepShaver's existing C++ flag
inheritance, and Xcode's project-specific includes and definitions.
Direct Xcode invocation can set `MACEMUS_CPPFLAGS` explicitly.

Basilisk II's generated CPU tools are *executables for the build host*,
not guest-target binaries. They use their own fixed include/definition
flags plus `HOST_CPPFLAGS` (`MACEMUS_HOST_CPPFLAGS` under Xcode).
Guest target CPPFLAGS are deliberately **not** forwarded to these
generator compilations or their link steps.

On Unix/MinGW, Autoconf uses CPPFLAGS during initial configuration and
the configured emulator Makefiles use CPPFLAGS in compilation. Their
internal includes are now appended with GNU make's `override` directive,
so a root command-line `CPPFLAGS=...` will not erase the paths.
Existing configured Makefiles must be regenerated to obtain this change;
the root Makefile intentionally does not rerun Autoconf unexpectedly.
Neither this change nor `make cppflags-info` verifies successful
native compilation.

### LDFLAGS: target linking versus build-host tools

The root Makefile now keeps the two linker flag namespaces separate:

```sh
make linker-info LDFLAGS='-Wl,-dead_strip -L/custom/lib'
make basilisk LDFLAGS='-L/custom/lib -Wl,-dead_strip'
make sheepshaver LDFLAGS='-Wl,-dead_strip'
make basilisk HOST_LDFLAGS='-L/host/tools/lib'
make test-linker-flags
```

* `LDFLAGS` belongs to the **emulator executable**. With Xcode it maps
  to the custom `MACEMUS_LDFLAGS` build setting, appended to the active
  architecture-specific `OTHER_LDFLAGS` without removing the CPU library
  or Intel-specific page-zero flags. On Unix/MinGW it stays in the
  existing `$(LDFLAGS)` link recipes.
* `HOST_LDFLAGS` is independent. It reaches the build-host CPU-generator
  links on macOS (via `MACEMUS_HOST_LDFLAGS`) and on Unix. Guest-target
  flags must not leak into executable generators. The Xcode CPU library
  projects are static archives, so their ordinary `OTHER_LDFLAGS` are
  not used like application link flags.
* Xcode's `OTHER_LDFLAGS[arch=arm64]` and
  `OTHER_LDFLAGS[arch=x86_64]` both preserve `$(inherited)` and the
  existing emulator-specific libraries. Use `MACEMUS_LDFLAGS` directly
  when invoking Xcode; overriding `OTHER_LDFLAGS` outright risks
  replacing required project flags.
* Keep linker flags (`-L`, `-Wl,`, `-rpath`) separate from
  preprocessing (`CPPFLAGS`) and library selections (`LIBS`,
  Xcode framework references). `LIBS` overrides on Unix are respected
  while SheepShaver's required GUI libraries remain appended.
  `-no_pie` and the explicit page-zero flags stay **x86-64 only**.

`make test-linker-flags` exercises Make's dry-run routing without
Xcode. Full linking and compatibility of native Homebrew libraries
must still be checked on macOS. Both active Xcode apps still reference
`SDL2.framework`, so a Homebrew SDL2 dylib is not automatically
substituted by this flag change. Existing Unix build directories require
reconfiguration to pick up the revised templates.

### Conversion checks for the macOS clipboard

Both emulator clipboard implementations previously narrowed Cocoa's 64-bit
`NSUInteger` scrap lengths into the emulated 32-bit allocation register,
then copied the original size. This could allocate less than it copied.
The implementations now reject out-of-range lengths before conversion and
copy exactly the checked size. The shared `mac_clip_bounds.h` also validates
two-byte style counts plus 20-byte records, signed style offsets and ranges
before `subdataWithRange:`, and PICT dimensions before narrowing them to
16-bit values. Fixed-size 68K trap arrays use explicit 32-bit conversions.

```sh
make test-type-conversions   # standalone C++11 test, no Xcode required
```

The regression test builds with `-Wall -Wextra -Wconversion
-Wsign-conversion -Werror` and exercises zero, boundary, overflow,
negative-offset, reversed-range, and oversized-image cases. This does
**not** imply that both complete Xcode targets build warning-free: the
remaining Cocoa/SDL and architecture-specific casts require native builds.

## Existing emulator build instructions

#### BasiliskII
```
macOS     x86_64 JIT / arm64 non-JIT
Linux x86 x86_64 JIT / arm64 non-JIT
MinGW x86        JIT
```
#### SheepShaver
```
macOS     x86_64 JIT / arm64 non-JIT
Linux x86 x86_64 JIT / arm64 non-JIT
MinGW x86        JIT
```
### How To Build
These builds need to be installed SDL2.0.14+ framework/library.

https://www.libsdl.org
#### BasiliskII
##### macOS
preparation:

Download gmp-6.2.1.tar.xz from https://gmplib.org.
```
$ cd ~/Downloads
$ tar xf gmp-6.2.1.tar.xz
$ cd gmp-6.2.1
$ ./configure --disable-shared
$ make
$ make check
$ sudo make install
```
Download mpfr-4.2.0.tar.xz from https://www.mpfr.org.
```
$ cd ~/Downloads
$ tar xf mpfr-4.2.0.tar.xz
$ cd mpfr-4.2.0
$ ./configure --disable-shared
$ make
$ make check
$ sudo make install
```

These older source-build commands install into the default prefix
(typically `/usr/local`). If using those libraries for arm64 builds,
pass that prefix explicitly to Xcode as explained above and confirm their
architectures first.

On an Intel Mac, the libraries should be cross-built.  
Change the `configure` command for both GMP and MPFR as follows, and ignore the `make check` command:
```
$ CFLAGS="-arch arm64" CXXFLAGS="$CFLAGS" ./configure -host=aarch64-apple-darwin --disable-shared 
```
(from https://github.com/kanjitalk755/macemu/pull/96)

about changing Deployment Target:  
If you build with an older version of Xcode, you can change Deployment Target to the minimum it supports or 10.7, whichever is greater.

build:
```
$ cd macemu/BasiliskII/src/MacOSX
$ xcodebuild build -project BasiliskII.xcodeproj -configuration Release
```

##### Linux
preparation (arm64 only): Install GMP and MPFR.
```
$ cd macemu/BasiliskII/src/Unix
$ ./autogen.sh
$ make
```
##### MinGW32/MSYS2
preparation:
```
$ pacman -S base-devel mingw-w64-i686-toolchain autoconf automake mingw-w64-i686-SDL2
```
note: MinGW32 dropped GTK2 package.
See msys2/MINGW-packages#24490

build (from a mingw32.exe prompt):
```
$ cd macemu/BasiliskII/src/Windows
$ ../Unix/autogen.sh
$ make
```
#### SheepShaver
##### macOS
about changing Deployment Target: see BasiliskII
```
$ cd macemu/SheepShaver/src/MacOSX
$ xcodebuild build -project SheepShaver_Xcode8.xcodeproj -configuration Release
```

##### Linux
```
$ cd macemu/SheepShaver/src/Unix
$ ./autogen.sh
$ make
```
For Raspberry Pi:
https://github.com/vaccinemedia/macemu

##### MinGW32/MSYS2
preparation: same as BasiliskII  
  
build (from a mingw32.exe prompt):
```
$ cd macemu/SheepShaver
$ make links
$ cd src/Windows
$ ../Unix/autogen.sh
$ make
```
### Recommended key bindings for gnome
https://github.com/kanjitalk755/macemu/blob/master/SheepShaver/doc/Linux/gnome_keybindings.txt

(from https://github.com/kanjitalk755/macemu/issues/59)
