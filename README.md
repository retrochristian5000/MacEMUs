# MacEMUs

MacEMUs collects Basilisk II and SheepShaver in one source tree, with shared
`cxmon` sources. The root Makefile coordinates the two emulators without
replacing their existing platform build systems.

## Installing with PREFIX and DESTDIR

Root `make install` builds and installs both emulators. `PREFIX` controls
the final installation root (default `/usr/local`); `DESTDIR` is an
optional absolute packaging/staging directory (default empty). The staging
root is never passed into compilation, Xcode, or Homebrew detection.

On macOS, app bundles go into `$(DESTDIR)$(PREFIX)/Applications`.
For example `make install PREFIX=/usr/local DESTDIR=/tmp/pkg` stages
`/tmp/pkg/usr/local/Applications/BasiliskII.app` and `SheepShaver.app`.
Use `PREFIX=/` for the normal macOS `/Applications` directory.
The script copies bundles with `ditto` when available. The root
Makefile sets `INSTALL_FLAGS ?= -f`, so **ordinary `make install`
replaces existing Basilisk II and SheepShaver apps automatically**.
There is no need to add `-f` to your command. Direct invocations of
the underlying script without `-f` still refuse to overwrite.

```sh
make install PREFIX=/usr/local DESTDIR=/tmp/pkg
make install-basilisk PREFIX=/
# Optional safety mode: refuse to overwrite an existing app
make install INSTALL_FLAGS=
```

The replacement process validates all sources and paths, copies new
bundles into a temporary directory, and moves existing bundles to
backups before renaming the fresh versions into place. It avoids merging
obsolete files, attempts rollback on failure, and retains backups if
rollback cannot complete. Setting `INSTALL_FLAGS=` disables force
for a particular invocation. The separate Unix installers already
overwrite installed files and do not use this macOS flag.

```sh
make install-info
make test-install
make install PREFIX=/usr/local DESTDIR=/tmp/pkg
make install-basilisk PREFIX=/
make install-sheepshaver PREFIX=/usr/local
```

The default source bundles are `BUILD_ROOT/BasiliskII/CONFIGURATION/`
and `BUILD_ROOT/SheepShaver/CONFIGURATION/`; override
`MACEMUS_BASILISK_APP` or `MACEMUS_SHEEPSHAVER_APP` if Xcode
uses a custom output directory. Both sources are checked before a
combined install, although an I/O failure during copying can leave
an incomplete destination.

On Unix, install delegates to the already-configured component Makefiles,
forwarding the lowercase Autoconf `prefix` and the staging `DESTDIR`.
If changing a configured prefix affects built-in data paths, reconfigure
and rebuild with the desired prefix. Root MinGW install is unsupported.

Staging is not standalone app distribution: Homebrew SDL2/SDL3 and other
external dylibs are not embedded or code-signed by this command.

## SheepShaver startup checks

On macOS, startup can stop at the host loader (architecture or dylibs), SDL
audio/video initialization, VM preferences, memory mapping, ROM file reading,
ROM patches, video driver initialization, or the guest boot drive.
ROM patching recognizes TNT, Alchemy, Zanzibar, Gazelle, Gossamer and NewWorld
ROM signatures; it does not imply that every ROM boots every classic Mac OS.
SheepShaver's established guest OS compatibility ends at Mac OS 9.0.4.
The parser's reference to a Mac OS 9.2.x *ROM image* is about a ROM
container, not support for Mac OS 9.2 as a booted guest.

Startup RAM preferences <=1000 are interpreted in MiB; values above that
are treated as bytes. A minimum 16 MiB is preserved. Negative RAM
preferences now fail rather than silently turning into huge unsigned
allocations, and fixed-addressing modes reject RAM overlapping the ROM.

The ROM loader now loops through interrupted/short reads, maintains a
terminating byte for text-based compressed-ROM metadata parsing, and
releases its buffer on failure. Compressed ROM offset and length fields
are validated against actual bytes read before decompression. This
does not prove all malformed ROM payloads can be decoded safely.

```sh
make test-sheepshaver-startup
make sheepshaver
```

The standalone boundary test cannot launch the emulator or validate
any particular ROM, boot image, SDL device or macOS dylib.

### Diagnosing SheepShaver.app exiting immediately

Previously the emulator reported startup errors only on stdout (invisible
in a Finder launch) and used exit status zero even for failed starts.
The startup path now logs diagnostic stages and errors to stderr and,
on macOS, to `~/Library/Logs/SheepShaver.log`.

```sh
tail -n 80 "$HOME/Library/Logs/SheepShaver.log"
make test-sheepshaver-app-logging
```

The last stage reached identifies whether failure occurred during SDL,
preferences, VM, RAM, ROM loading, device initialization, or boot.
Startup failures now exit nonzero, `vm_init()` errors are checked, and
guest, host system, and preference teardown is conditional on successful
initialization. Early loader errors (dyld, missing dylibs) can occur
before this log opens; use Console or launch the app binary from a shell
for those. The regression test checks source-level invariants; a real
macOS launch is necessary to identify the actual failure on that host.

### ROM discovery and early SheepShaver configuration

The native SheepShaver app searches the configured `rom` preference
(or `ROM` if the preference is empty), then `Mac OS ROM` as fallback.
For a Finder-opened app, its working directory normally becomes the
directory **containing** `SheepShaver.app`. A file named `Mac OS ROM`
beside the app can therefore be found. If a Terminal invocation
already starts in a directory containing `ROM` or `Mac OS ROM`,
SheepShaver now preserves that working directory instead.

The Xcode SheepShaver.app already includes `VMSettingsWindow.nib` and
`VMSettingsController`, but its built-in `PrefsEditor()` was a dummy.
The new `--settings` (or `--gui`) entry point opens that Cocoa window
before SDL, guest RAM allocation, or ROM loading. Missing SDL video
or a missing ROM cannot block the configuration-only entry point.

```sh
make sheepshaver-settings
"/Applications/SheepShaver.app/Contents/MacOS/SheepShaver" --settings
```

Ordinary app launches with no readable ROM candidate automatically
open the Cocoa settings window (unless `nogui` is enabled). After
saving or closing settings, relaunch to attempt guest boot. macOS
preferences normally live in `~/.sheepshaver_prefs`; explicitly
selected `.sheepvm` directories use their own `prefs` file instead.
Having a ROM alone does not guarantee a bootable classic Mac OS disk.

```sh
make test-sheepshaver-configuration
tail -n 80 "$HOME/Library/Logs/SheepShaver.log"
```

The portable test covers ROM fallback logic and source wiring; Cocoa
display and actual ROM/guest boot require a native macOS runtime.

### Experimental Mac OS 9.2.x groundwork

New World Mac OS 9.2.x requires a guest PowerPC32 MMU (BAT,
hashed page tables, SR/SDR1, DSI/ISI) and a nanokernel v2
boot/hardware contract, not simply an accepted ROM version string.
The experimental GPL-compatible MMU implementation and synthetic
translation/fault tests live under `SheepShaver/src/kpx_cpu` and
`tests/` and are **not yet linked into the live emulator**.

```sh
make test-sheepshaver-92-mmu
```

See `docs/SheepShaver-MacOS-9.2.2.md` for donor attribution, supported
and unsupported claims, validation gates, and remaining hardware work.
Mac OS 9.2.2 is **not claimed to boot** in this fork.

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

**Native-only Xcode builds:** On Apple Silicon, root make selects
`ARCHS=arm64` and builds only `uae_cpu_arm64` before the Basilisk II
application. On Intel, it selects native `x86_64` and builds
`uae_cpu_x86_64`. The previous Basilisk II app target unconditionally
depended on **both** CPU subprojects, which inadvertently triggered an
x86_64 build on Apple Silicon. Those automatic dependencies are now
removed, while both original CPU projects remain available for their
respective native hosts.

Root make passes `ARCHS`, `ONLY_ACTIVE_ARCH=YES`, and `HOST_ARCH`
to every Xcode invocation after `XCODE_ARGS`. Each selected CPU
archive shares `SYMROOT`/`OBJROOT` with the application; the app
explicitly searches `BUILT_PRODUCTS_DIR` for its native archive.
SheepShaver's CPU backend also uses the native host architecture.

A Rosetta-translated macOS shell is rejected; open a native Terminal
session. Run `make native-info` and `make test-native-xcode` to inspect
the selected build graph. Direct Xcode Basilisk II builds require the
matching CPU library to be built separately first: the root Makefile
performs that preparation automatically. Guest CPU emulation
(68K/PowerPC) does not require an Intel host binary.

```sh
make native-info
make test-native-xcode
make basilisk
```

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

**SDL2 library/framework selection:** The two active Xcode projects no
longer have hard-coded SDL2.framework file references, link-phase entries,
or unconditional framework embedding. They use
`MACEMUS_SDL2_LINK_FLAGS` in architecture-specific `OTHER_LDFLAGS` instead.
The root Makefile automatically prefers Homebrew's common
`lib/libSDL2.dylib`, then the formula's `lib/libSDL2.dylib`, setting
`MACEMUS_SDL2_LIBRARY_DIR` and passing **the selected dylib's absolute
path** to Xcode. This avoids accidentally linking a different SDL2
implementation found earlier in `LIBRARY_SEARCH_PATHS`. Otherwise it
selects `-framework SDL2`, which requires a real installed framework.

```sh
make homebrew-info
make test-sdl2-linkage
make basilisk MACEMUS_SDL2_LINKAGE=dylib
make sheepshaver MACEMUS_SDL2_LINKAGE=framework
make basilisk MACEMUS_SDL2_LINKAGE=dylib MACEMUS_SDL2_LIBRARY_DIR=/custom/lib
```

Forced `dylib` mode fails immediately if `libSDL2.dylib` is absent.
Direct `xcodebuild` defaults to `-framework SDL2`; to use a dylib
directly, specify `MACEMUS_SDL2_LINK_FLAGS=/path/to/lib/libSDL2.dylib`
and `MACEMUS_SDL2_LIBRARY_DIR=/path/to/lib`. Framework mode preserves
`FRAMEWORK_SEARCH_PATHS` for real SDL2.framework installations.

**Runtime limitation:** Neither route embeds relocatable SDL libraries.
Homebrew's SDL2 compatibility dylib depends on SDL3, so standalone
application bundles need separate dependency-copying, install-name,
architecture, and code-signing work. Existing `-lmpfr`/`-lgmp`
and emulator CPU-library linking remains unchanged.

### Homebrew framework directory (macOS)

Homebrew has an optional common `Frameworks` directory alongside
`bin`, `include`, and `lib`. The root Makefile now discovers
`$(brew --prefix)/Frameworks` and, **only if the directory exists**,
passes it to both active Xcode projects as `MACEMUS_FRAMEWORK_SEARCH_DIR`.
They include this in `FRAMEWORK_SEARCH_PATHS` while retaining inherited
framework locations and the previous `/Library/Frameworks` fallback.
The search path also works for an explicit alternate directory:

```sh
make homebrew-info
make test-homebrew-frameworks
make basilisk MACEMUS_BREW_FRAMEWORKS=/custom/Frameworks
make sheepshaver XCODE_ARGS='MACEMUS_FRAMEWORK_SEARCH_DIR=/custom/Frameworks'
```

**SDL2 distinction:** Homebrew's standard `sdl2-compat` formula
installs SDL2-compatible headers and a dynamic library built on SDL3;
it does **not** guarantee an `SDL2.framework` inside Homebrew's
`Frameworks` directory. The Xcode projects previously had absolute SDL2.framework references;
these have now been replaced by a selected dylib path or
`-framework SDL2` linker options. The framework search path is retained
for genuine installed frameworks, but no fake framework symlinks are created.

### Diagnose missing SDL2 exports on macOS

`sdl2-compat` implements and exports SDL2 APIs, while using SDL3
internally. **Do not automatically add `-lSDL3`** to source that uses
the SDL2 API. Adding it can hide a wrong SDL2 binary/header combination
rather than solve the underlying mismatch.

```sh
make homebrew-info
make check-sdl2-exports
make check-sdl2-exports MACEMUS_SDL2_TEST_ARCH=arm64
make check-sdl2-exports SDL2_EXPECT_EXPORTS='SDL_CreateThread SDL_OpenAudioDevice'
```

On macOS, the check uses the same selected SDL2 library and header paths
as the root Makefile. It verifies a Mach-O architecture slice with
`lipo`, compares required `_SDL_*` exports with `nm`, prints the
dylib's linked dependencies using `otool -L`, then runs a small
**compile-and-link-only** test with `xcrun clang`. The test calls common
SDL2 APIs from MacEMUs and never launches SDL or the emulator.
`SDL2_EXPECT_EXPORTS` accepts additional names from a real undefined
symbols report. The built-in probe includes `SDL_Init`, `SDL_Quit`,
`SDL_GetError`, `SDL_OpenAudio`, `SDL_MixAudio`,
`SDL_CreateRenderer`, and the mutex group:
`SDL_CreateMutex`, `SDL_LockMutex`, `SDL_UnlockMutex`, and
`SDL_DestroyMutex`. The executable uses the selected SDL2 dylib's
**exact path**, not an ambiguous `-lSDL2` lookup.

This diagnostic currently requires a selected `libSDL2.dylib` and a
matching `SDL.h` under Homebrew or the chosen alternate prefix. It
reports that **framework mode needs a separate file-specific audit**,
rather than claiming to have verified a framework. If the selected
library is missing symbols, verify the installed sdl2-compat version
and architecture. If the small link succeeds but the full project
fails, inspect the exact missing symbol(s) and Xcode's effective
`OTHER_LDFLAGS`, compilation macros, and target architecture.

Passing the export check establishes only that the probed SDL2 symbols
are exported and linkable; it does **not** verify all SDL2 APIs, correct
runtime library loading, bundled SDL3 dependencies, or native emulator
startup.

### SDL compatibility dependency audit

The current SDL source modules use **core SDL2** calls rather than
SDL2_image (`IMG_*`), SDL2_mixer (`Mix_*`), SDL2_ttf (`TTF_*`),
or SDL2_net (`SDLNet_*`). The core functions `SDL_MixAudio` and `SDL_UnlockMutex` are
**not** supplied by SDL2_mixer. Adding optional SDL libraries without
corresponding source calls would not solve missing `_SDL_*` exports.

`sdl2-compat` wraps the SDL2 API with SDL3 at runtime. SDL3 can be
loaded dynamically by the wrapper, so an `otool -L libSDL2.dylib`
listing that does not mention SDL3 is **not** proof that SDL3 is
unnecessary. To check both the build's SDL2 symbols and an actual
SDL3-backed, headless initialization:

```sh
make audit-sdl-addons
make check-sdl2-exports
MACEMUS_SDL2_RUNTIME_TEST=1 make check-sdl2-exports
```

The active Basilisk II and SheepShaver Xcode application targets also
compile with `MACEMUS_EXPECT_SDL2=1`. Their shared `my_sdl.h` and
`SDLMain.m` reject incompatible SDL1/SDL3 headers in these SDL2
builds. This guards against accidentally activating legacy SDL1.2
code because `SDL.h` resolves to a different SDK or framework.

**Interpret missing symbols by family.** `_SDL_*` generally
indicates the SDL core ABI or library selection, and requires the
exact symbol name. `_IMG_*`, `_Mix_*`, `_TTF_*` or
`_SDLNet_*` points to a separately linked extension *only when
that API is actually called*. `dyld` failures locating SDL3 at
runtime are a different problem from the linker's `Undefined
symbols for architecture` errors. The runtime probe checks
`SDL_Init(0)` only, with no audio or video device requested.
Successful probes still do not validate the full emulator runtime
or a redistributable app bundle.

### Specific undefined symbol: `_SDL_UnlockMutex`

Upstream `sdl2-compat` implements `SDL_UnlockMutex` as a core SDL2
entry point that forwards to SDL3 and returns an SDL2-compatible `int`.
It is not an SDL2_mixer, SDL2_net, SDL2_image, or SDL2_ttf export.
SDL3's native `SDL_UnlockMutex` has a different (`void`) return type,
so linking SDL3 directly is not a safe substitute for an SDL2 binary.

When the linker reports `Undefined symbols for architecture arm64:
"_SDL_UnlockMutex"`, test the actual selected library:

```sh
make check-sdl2-exports MACEMUS_SDL2_TEST_ARCH=arm64 \
  SDL2_EXPECT_EXPORTS='SDL_UnlockMutex SDL_LockMutex'
```

If this check fails at `nm`, inspect the specific SDL2 dylib's exports,
install state, and architecture. If `nm` and the standalone link probe
pass but Xcode fails, inspect Xcode's full linker invocation and ensure
the matching SDL2 dylib is on that line (not merely a `-L` search path).
The root Makefile now passes the selected dylib's absolute path to avoid
accidental selection of another SDL2 build. The Xcode projects' existing
custom `MACEMUS_SDL2_LINK_FLAGS` setting accepts this exact path without
new project-file references.

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
must still be checked on macOS. The active Xcode projects now select
SDL2 linking explicitly through `MACEMUS_SDL2_LINK_FLAGS`. Existing Unix build directories require
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
