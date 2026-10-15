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

For Apple Silicon, Basilisk II's arm64 CPU uses GMP and MPFR development
libraries. The Xcode arm64 header/library search paths default to the native
Homebrew prefix `/opt/homebrew`; x86_64 link search paths remain at
`/usr/local/lib`. If the arm64 libraries are installed elsewhere, pass
`XCODE_ARGS='MACEMUS_ARM64_PREFIX=/path/to/prefix'`. Verify that GMP,
MPFR, and SDL2 binaries contain the architecture(s) you intend to ship;
setting a search path cannot convert Intel-only libraries to arm64.

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
make all XCODE_ARGS='MACEMUS_ARM64_PREFIX=/opt/homebrew'
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

The root `make` entry point detects the running host architecture and
queries Homebrew at build startup. On native Apple Silicon, it checks
`brew --prefix --installed gmp` and `brew --prefix --installed mpfr` and
passes their stable per-formula prefixes into the Basilisk II Xcode build.
Keg-only formulae do not need to be forcibly linked. If Homebrew is not
installed, the previous Xcode search settings remain usable.

```sh
make homebrew-info                  # inspect Homebrew and detected formulae
make basilisk                      # auto-discover libraries (if installed)
make all                           # both emulators
make basilisk MACEMUS_HOMEBREW=off  # disable discovery
make basilisk MACEMUS_HOMEBREW=required # error if Homebrew is missing
make basilisk MACEMUS_BREW=/custom/bin/brew
```

`XCODE_ARGS` comes last, so explicit overrides such as
`XCODE_ARGS='MACEMUS_GMP_PREFIX=/custom/gmp MACEMUS_MPFR_PREFIX=/custom/mpfr'`
take priority. Direct Xcode builds retain their existing fallback prefixes.
The shell architecture and formula binary architectures must match; an Intel
Homebrew installation under Rosetta is **not** automatically used for arm64
linking.

**SDL2 limitation:** Both current Xcode projects still refer to
`/Library/Frameworks/SDL2.framework`. `make homebrew-info` reports a
Homebrew SDL2 formula if installed, but the Homebrew `libSDL2.dylib` cannot
satisfy those existing framework references. SDL2 library-style linking and
app bundling require a separate Xcode integration change; no filesystem
symlinks or forced Homebrew links are created here.

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
