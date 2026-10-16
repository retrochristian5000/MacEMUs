# MacEMUs top-level build coordinator. Component build files remain authoritative.
.DEFAULT_GOAL := all

HOST_OS := $(shell uname -s)
ifeq ($(HOST_OS),Darwin)
DEFAULT_MACEMUS_PLATFORM := macos
else ifneq ($(filter MINGW% MSYS% CYGWIN%,$(HOST_OS)),)
DEFAULT_MACEMUS_PLATFORM := mingw
else
DEFAULT_MACEMUS_PLATFORM := unix
endif
MACEMUS_PLATFORM ?= $(DEFAULT_MACEMUS_PLATFORM)

ifeq ($(filter $(MACEMUS_PLATFORM),macos unix mingw),)
$(error Unsupported MACEMUS_PLATFORM '$(MACEMUS_PLATFORM)'; use macos, unix, or mingw)
endif

XCODEBUILD ?= xcodebuild
CONFIGURATION ?= Release
BUILD_ROOT ?= $(CURDIR)/build
XCODE_ARGS ?=
CONFIGURE_ARGS ?=

# PREFIX is the installed layout; DESTDIR is the packaging/staging root.
PREFIX ?= /usr/local
DESTDIR ?=
# Reinstall existing macOS applications by default; backup/rollback is handled
# by scripts/install-macos-app.sh. INSTALL_FLAGS= opts out of replacement.
INSTALL_FLAGS ?= -f
ifneq ($(strip $(INSTALL_FLAGS)),)
ifneq ($(strip $(INSTALL_FLAGS)),-f)
$(error INSTALL_FLAGS supports only -f)
endif
endif
MACEMUS_BASILISK_APP ?= $(BUILD_ROOT)/BasiliskII/$(CONFIGURATION)/BasiliskII.app
MACEMUS_SHEEPSHAVER_APP ?= $(BUILD_ROOT)/SheepShaver/$(CONFIGURATION)/SheepShaver.app

# CPPFLAGS are compile-time preprocessing options (-I/-D/-U), not link flags.
# Pass them to Xcode's C and C++ compiler settings, preserving native headers.
# Host generator tools have an independent HOST_CPPFLAGS namespace.
CPPFLAGS ?=
HOST_CPPFLAGS ?=
# Linker driver options, e.g. -Ldir, -Wl,-option and rpath.
# Never forward target flags to host-side CPU generators.
LDFLAGS ?=
HOST_LDFLAGS ?=
MACEMUS_XCODE_LINK_ARGS :=
ifneq ($(strip $(LDFLAGS)),)
MACEMUS_XCODE_LINK_ARGS += MACEMUS_LDFLAGS="$(LDFLAGS)"
endif
ifneq ($(strip $(HOST_LDFLAGS)),)
MACEMUS_XCODE_LINK_ARGS += MACEMUS_HOST_LDFLAGS="$(HOST_LDFLAGS)"
endif
MACEMUS_XCODE_CPP_ARGS :=
ifneq ($(strip $(CPPFLAGS)),)
MACEMUS_XCODE_CPP_ARGS += MACEMUS_CPPFLAGS="$(CPPFLAGS)"
endif
ifneq ($(strip $(HOST_CPPFLAGS)),)
MACEMUS_XCODE_CPP_ARGS += MACEMUS_HOST_CPPFLAGS="$(HOST_CPPFLAGS)"
endif

# Homebrew is optional. Prefer its common bin/include/lib prefix rather than
# querying every installed formula. Unlinked (including keg-only) GMP/MPFR
# installations are resolved only when shared headers or libraries are absent.
# Never mix native arm64 dependencies with an Intel/Rosetta build.
MACEMUS_HOMEBREW ?= auto
MACEMUS_HOST_ARCH := $(shell uname -m)
# macOS host code must be native-only; Rosetta is not native ARM64.
ifeq ($(MACEMUS_PLATFORM),macos)
ifeq ($(filter $(MACEMUS_HOST_ARCH),arm64 x86_64),)
$(error Unsupported macOS native architecture: $(MACEMUS_HOST_ARCH))
endif
ifeq ($(HOST_OS),Darwin)
MACEMUS_RUNNING_TRANSLATED := $(shell sysctl -n sysctl.proc_translated 2>/dev/null || :)
ifeq ($(MACEMUS_RUNNING_TRANSLATED),1)
$(error Running under Rosetta; use a native arm64 Terminal session)
endif
endif
endif
ifneq ($(filter $(MACEMUS_HOMEBREW),auto off required),$(MACEMUS_HOMEBREW))
$(error MACEMUS_HOMEBREW must be auto, off, or required)
endif

MACEMUS_XCODE_BREW_ARGS :=
MACEMUS_XCODE_ENV :=
ifeq ($(MACEMUS_PLATFORM),macos)
ifneq ($(MACEMUS_HOMEBREW),off)
MACEMUS_BREW ?= $(shell \
	if test "$(MACEMUS_HOST_ARCH)" = arm64 && test -x /opt/homebrew/bin/brew; then \
		printf '%s' /opt/homebrew/bin/brew; \
	elif test "$(MACEMUS_HOST_ARCH)" = x86_64 && test -x /usr/local/bin/brew; then \
		printf '%s' /usr/local/bin/brew; \
	elif command -v brew >/dev/null 2>&1; then \
		command -v brew; \
	fi)
# Freeze discovery once to avoid repeated brew invocations during expansion.
MACEMUS_BREW := $(MACEMUS_BREW)
ifneq ($(strip $(MACEMUS_BREW)),)
MACEMUS_BREW_PREFIX ?= $(shell "$(MACEMUS_BREW)" --prefix 2>/dev/null)
endif
MACEMUS_BREW_PREFIX := $(MACEMUS_BREW_PREFIX)
# Locate optional SDL2 compatibility headers and dylibs; Xcode now selects
# shared-library or real-framework linkage without unconditional embedding.
MACEMUS_SDL2_PREFIX ?= $(shell \
	if test -n "$(MACEMUS_BREW)" && test -n "$(MACEMUS_BREW_PREFIX)"; then \
		"$(MACEMUS_BREW)" --prefix --installed sdl2-compat 2>/dev/null || \
		"$(MACEMUS_BREW)" --prefix --installed sdl2 2>/dev/null || :; \
	fi)
ifneq ($(strip $(MACEMUS_BREW_PREFIX)),)
MACEMUS_BREW_BIN := $(MACEMUS_BREW_PREFIX)/bin
MACEMUS_BREW_INCLUDE := $(MACEMUS_BREW_PREFIX)/include
MACEMUS_BREW_LIB := $(MACEMUS_BREW_PREFIX)/lib
# Homebrew's shared framework directory is separate from include/ and lib/.
# Feed it to Xcode only when it exists; never assume SDL2.framework lives there.
MACEMUS_BREW_FRAMEWORKS ?= $(MACEMUS_BREW_PREFIX)/Frameworks
ifneq ($(wildcard $(MACEMUS_BREW_FRAMEWORKS)/.),)
MACEMUS_XCODE_BREW_ARGS += MACEMUS_FRAMEWORK_SEARCH_DIR="$(MACEMUS_BREW_FRAMEWORKS)"
endif
# SDL2 compatibility headers can be included as <SDL2/SDL.h> or <SDL.h>.
# Try the Homebrew common prefix first; an unlinked formula is a fallback.
MACEMUS_SDL2_INCLUDE_PREFIX ?= $(MACEMUS_BREW_PREFIX)
ifneq ($(wildcard $(MACEMUS_SDL2_INCLUDE_PREFIX)/include/SDL2/SDL.h),)
MACEMUS_SDL2_INCLUDE_ROOT := $(MACEMUS_SDL2_INCLUDE_PREFIX)/include
MACEMUS_SDL2_INCLUDE_FLAT := $(MACEMUS_SDL2_INCLUDE_PREFIX)/include/SDL2
else
ifneq ($(strip $(MACEMUS_SDL2_PREFIX)),)
ifneq ($(wildcard $(MACEMUS_SDL2_PREFIX)/include/SDL2/SDL.h),)
MACEMUS_SDL2_INCLUDE_ROOT := $(MACEMUS_SDL2_PREFIX)/include
MACEMUS_SDL2_INCLUDE_FLAT := $(MACEMUS_SDL2_PREFIX)/include/SDL2
endif
endif
endif
ifneq ($(strip $(MACEMUS_SDL2_INCLUDE_ROOT)),)
MACEMUS_XCODE_BREW_ARGS += MACEMUS_SDL2_HEADER_ROOT="$(MACEMUS_SDL2_INCLUDE_ROOT)"
MACEMUS_XCODE_BREW_ARGS += MACEMUS_SDL2_HEADER_FLAT="$(MACEMUS_SDL2_INCLUDE_FLAT)"
endif
# Project-scoped executable lookup; do not modify the user's shell startup.
MACEMUS_XCODE_ENV := PATH="$(MACEMUS_BREW_BIN):$$PATH"
ifneq ($(strip $(MACEMUS_BREW)),)
MACEMUS_GMP_PREFIX ?= $(shell \
	if test ! -f "$(MACEMUS_BREW_INCLUDE)/gmp.h" || \
	   { test ! -f "$(MACEMUS_BREW_LIB)/libgmp.dylib" && test ! -f "$(MACEMUS_BREW_LIB)/libgmp.a"; }; then \
		"$(MACEMUS_BREW)" --prefix --installed gmp 2>/dev/null || :; \
	fi)
MACEMUS_MPFR_PREFIX ?= $(shell \
	if test ! -f "$(MACEMUS_BREW_INCLUDE)/mpfr.h" || \
	   { test ! -f "$(MACEMUS_BREW_LIB)/libmpfr.dylib" && test ! -f "$(MACEMUS_BREW_LIB)/libmpfr.a"; }; then \
		"$(MACEMUS_BREW)" --prefix --installed mpfr 2>/dev/null || :; \
	fi)
endif
MACEMUS_GMP_PREFIX := $(MACEMUS_GMP_PREFIX)
MACEMUS_MPFR_PREFIX := $(MACEMUS_MPFR_PREFIX)
ifeq ($(MACEMUS_HOST_ARCH),arm64)
MACEMUS_XCODE_BREW_ARGS += MACEMUS_ARM64_PREFIX="$(MACEMUS_BREW_PREFIX)"
ifneq ($(strip $(MACEMUS_GMP_PREFIX)),)
MACEMUS_XCODE_BREW_ARGS += MACEMUS_GMP_PREFIX="$(MACEMUS_GMP_PREFIX)"
endif
ifneq ($(strip $(MACEMUS_MPFR_PREFIX)),)
MACEMUS_XCODE_BREW_ARGS += MACEMUS_MPFR_PREFIX="$(MACEMUS_MPFR_PREFIX)"
endif
else ifeq ($(MACEMUS_HOST_ARCH),x86_64)
MACEMUS_XCODE_BREW_ARGS += MACEMUS_X86_64_PREFIX="$(MACEMUS_BREW_PREFIX)"
endif
endif
endif
ifeq ($(MACEMUS_HOMEBREW),required)
ifeq ($(strip $(MACEMUS_BREW_PREFIX)),)
$(error Homebrew requested but not found; set MACEMUS_BREW or use MACEMUS_HOMEBREW=auto)
endif
endif
endif

# Choose SDL2-compatible linkage at Make startup. sdl2-compat provides
# libSDL2.dylib rather than an SDL2.framework; never fake a framework path.
MACEMUS_SDL2_LINKAGE ?= auto
MACEMUS_SDL2_LIBRARY_DIR ?=
MACEMUS_XCODE_SDL_ARGS :=
ifeq ($(MACEMUS_PLATFORM),macos)
ifeq ($(filter $(MACEMUS_SDL2_LINKAGE),auto dylib framework),)
$(error MACEMUS_SDL2_LINKAGE must be auto, dylib, or framework)
endif
ifneq ($(MACEMUS_HOMEBREW),off)
ifeq ($(strip $(MACEMUS_SDL2_LIBRARY_DIR)),)
ifneq ($(strip $(MACEMUS_BREW_PREFIX)),)
ifneq ($(wildcard $(MACEMUS_BREW_LIB)/libSDL2.dylib),)
MACEMUS_SDL2_LIBRARY_DIR := $(MACEMUS_BREW_LIB)
endif
endif
ifeq ($(strip $(MACEMUS_SDL2_LIBRARY_DIR)),)
ifneq ($(strip $(MACEMUS_SDL2_PREFIX)),)
ifneq ($(wildcard $(MACEMUS_SDL2_PREFIX)/lib/libSDL2.dylib),)
MACEMUS_SDL2_LIBRARY_DIR := $(MACEMUS_SDL2_PREFIX)/lib
endif
endif
endif
endif
endif
# Explicitly requested dylib locations must contain a real binary.
ifneq ($(strip $(MACEMUS_SDL2_LIBRARY_DIR)),)
ifeq ($(wildcard $(MACEMUS_SDL2_LIBRARY_DIR)/libSDL2.dylib),)
$(error SDL2 shared library not found at $(MACEMUS_SDL2_LIBRARY_DIR)/libSDL2.dylib)
endif
endif
ifeq ($(MACEMUS_SDL2_LINKAGE),dylib)
ifeq ($(wildcard $(MACEMUS_SDL2_LIBRARY_DIR)/libSDL2.dylib),)
$(error SDL2 shared library not found; install sdl2-compat or set MACEMUS_SDL2_LIBRARY_DIR)
endif
endif
ifeq ($(MACEMUS_SDL2_LINKAGE),framework)
MACEMUS_SDL2_SELECTED := framework
else ifneq ($(strip $(MACEMUS_SDL2_LIBRARY_DIR)),)
MACEMUS_SDL2_SELECTED := dylib
else
MACEMUS_SDL2_SELECTED := framework
endif
ifeq ($(MACEMUS_SDL2_SELECTED),dylib)
# The absolute dylib path pins the actual compatibility implementation.
# Relying on -lSDL2 can select a different SDL2 binary from earlier -L paths.
MACEMUS_XCODE_SDL_ARGS += MACEMUS_SDL2_LINK_FLAGS="$(MACEMUS_SDL2_LIBRARY_DIR)/libSDL2.dylib"
MACEMUS_XCODE_SDL_ARGS += MACEMUS_SDL2_LIBRARY_DIR="$(MACEMUS_SDL2_LIBRARY_DIR)"
else
MACEMUS_XCODE_SDL_ARGS += MACEMUS_SDL2_LINK_FLAGS="-framework SDL2"
endif
endif

# Build one matching CPU library before the Basilisk application, rather
# than Xcode recursively compiling both fixed-arch CPU subprojects.
MACEMUS_XCODE_NATIVE_ARGS :=
MACEMUS_BASILISK_CPU_PROJECT :=
MACEMUS_BASILISK_CPU_TARGET :=
ifeq ($(MACEMUS_PLATFORM),macos)
MACEMUS_XCODE_NATIVE_ARGS += ARCHS="$(MACEMUS_HOST_ARCH)" ONLY_ACTIVE_ARCH=YES HOST_ARCH="$(MACEMUS_HOST_ARCH)"
ifeq ($(MACEMUS_HOST_ARCH),arm64)
MACEMUS_BASILISK_CPU_PROJECT := BasiliskII/src/MacOSX/uae_cpu_2021.xcodeproj
MACEMUS_BASILISK_CPU_TARGET := uae_cpu_arm64
else
MACEMUS_BASILISK_CPU_PROJECT := BasiliskII/src/MacOSX/uae_cpu.xcodeproj
MACEMUS_BASILISK_CPU_TARGET := uae_cpu_x86_64
endif
endif

.PHONY: all basilisk sheepshaver install install-basilisk install-sheepshaver install-info test-install clean clean-basilisk clean-sheepshaver help homebrew-info cppflags-info linker-info test-linker-flags test-type-conversions test-homebrew-frameworks test-sdl2-linkage check-sdl2-exports audit-sdl-addons test-native-xcode native-info test-sheepshaver-startup test-sheepshaver-app-logging test-sheepshaver-configuration test-sheepshaver-boot-debugger sheepshaver-settings test-sheepshaver-92-mmu test-sheepshaver-92-registers test-sheepshaver-mmu-link test-sheepshaver-register-layout test-sheepshaver-rom-verification check-sheepshaver-rom

all: basilisk sheepshaver

install-info:
	@printf 'PREFIX=%s\nDESTDIR=%s\nINSTALL_FLAGS=%s\n' '$(PREFIX)' '$(DESTDIR)' '$(INSTALL_FLAGS)'
	@printf 'macOS app destination: %s%s/Applications\n' '$(DESTDIR)' '$(PREFIX)'
	@printf 'Built apps: %s | %s\n' '$(MACEMUS_BASILISK_APP)' '$(MACEMUS_SHEEPSHAVER_APP)'

test-install:
	@./tests/test-install.sh

ifeq ($(MACEMUS_PLATFORM),macos)
# Bundle copy is separate from the Xcode build and its INSTALL_PATH.
install: all
	@./scripts/install-macos-app.sh $(INSTALL_FLAGS) "$(DESTDIR)" "$(PREFIX)" "$(MACEMUS_BASILISK_APP)" "$(MACEMUS_SHEEPSHAVER_APP)"

install-basilisk: basilisk
	@./scripts/install-macos-app.sh $(INSTALL_FLAGS) "$(DESTDIR)" "$(PREFIX)" "$(MACEMUS_BASILISK_APP)"

install-sheepshaver: sheepshaver
	@./scripts/install-macos-app.sh $(INSTALL_FLAGS) "$(DESTDIR)" "$(PREFIX)" "$(MACEMUS_SHEEPSHAVER_APP)"

# Build native CPU archive first, sharing configuration and output directories.
basilisk:
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project $(MACEMUS_BASILISK_CPU_PROJECT) -target $(MACEMUS_BASILISK_CPU_TARGET) \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/BasiliskII" \
		OBJROOT="$(BUILD_ROOT)/BasiliskII/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(XCODE_ARGS) $(MACEMUS_XCODE_NATIVE_ARGS) build
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project BasiliskII/src/MacOSX/BasiliskII.xcodeproj -target BasiliskII \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/BasiliskII" \
		OBJROOT="$(BUILD_ROOT)/BasiliskII/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(MACEMUS_XCODE_SDL_ARGS) $(XCODE_ARGS) $(MACEMUS_XCODE_NATIVE_ARGS) build

sheepshaver:
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj -target SheepShaver \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/SheepShaver" \
		OBJROOT="$(BUILD_ROOT)/SheepShaver/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(MACEMUS_XCODE_SDL_ARGS) $(XCODE_ARGS) $(MACEMUS_XCODE_NATIVE_ARGS) build

clean-basilisk:
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project BasiliskII/src/MacOSX/BasiliskII.xcodeproj -target BasiliskII \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/BasiliskII" \
		OBJROOT="$(BUILD_ROOT)/BasiliskII/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(MACEMUS_XCODE_SDL_ARGS) $(XCODE_ARGS) $(MACEMUS_XCODE_NATIVE_ARGS) clean
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project $(MACEMUS_BASILISK_CPU_PROJECT) -target $(MACEMUS_BASILISK_CPU_TARGET) \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/BasiliskII" \
		OBJROOT="$(BUILD_ROOT)/BasiliskII/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(XCODE_ARGS) $(MACEMUS_XCODE_NATIVE_ARGS) clean

clean-sheepshaver:
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj -target SheepShaver \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/SheepShaver" \
		OBJROOT="$(BUILD_ROOT)/SheepShaver/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(MACEMUS_XCODE_SDL_ARGS) $(XCODE_ARGS) $(MACEMUS_XCODE_NATIVE_ARGS) clean

else
ifeq ($(MACEMUS_PLATFORM),mingw)
BUILD_SUBDIR := Windows
AUTOGEN := ../Unix/autogen.sh
else
BUILD_SUBDIR := Unix
AUTOGEN := ./autogen.sh
endif

# Autogen only if no configured Makefile exists; leave existing flags intact.
basilisk:
	@if test ! -f BasiliskII/src/$(BUILD_SUBDIR)/Makefile; then \
		echo 'Configuring Basilisk II ($(MACEMUS_PLATFORM))'; \
		(cd BasiliskII/src/$(BUILD_SUBDIR) && $(AUTOGEN) $(CONFIGURE_ARGS)) || exit $$?; \
	fi
	+$(MAKE) -C BasiliskII/src/$(BUILD_SUBDIR)

sheepshaver:
ifeq ($(MACEMUS_PLATFORM),mingw)
	@if test ! -e SheepShaver/src/Windows/m4; then \
		echo 'SheepShaver needs its Windows source links.' >&2; \
		echo 'Review SheepShaver/Makefile, then run: make -C SheepShaver links' >&2; \
		exit 1; \
	fi
endif
	@if test ! -f SheepShaver/src/$(BUILD_SUBDIR)/Makefile; then \
		echo 'Configuring SheepShaver ($(MACEMUS_PLATFORM))'; \
		(cd SheepShaver/src/$(BUILD_SUBDIR) && $(AUTOGEN) $(CONFIGURE_ARGS)) || exit $$?; \
	fi
	+$(MAKE) -C SheepShaver/src/$(BUILD_SUBDIR)

clean-basilisk:
	@if test -f BasiliskII/src/$(BUILD_SUBDIR)/Makefile; then \
		$(MAKE) -C BasiliskII/src/$(BUILD_SUBDIR) clean; \
	fi

clean-sheepshaver:
	@if test -f SheepShaver/src/$(BUILD_SUBDIR)/Makefile; then \
		$(MAKE) -C SheepShaver/src/$(BUILD_SUBDIR) clean; \
	fi
endif

# Unix installers already support Autoconf prefix + DESTDIR. Windows does not.
ifneq ($(MACEMUS_PLATFORM),macos)
ifeq ($(MACEMUS_PLATFORM),mingw)
install install-basilisk install-sheepshaver:
	@printf '%s\n' 'Root install is unsupported for MinGW; use Windows packaging.' >&2
	@exit 1
else
install: all
	+$(MAKE) -C BasiliskII/src/Unix prefix="$(PREFIX)" DESTDIR="$(DESTDIR)" install
	+$(MAKE) -C SheepShaver/src/Unix prefix="$(PREFIX)" DESTDIR="$(DESTDIR)" install
install-basilisk: basilisk
	+$(MAKE) -C BasiliskII/src/Unix prefix="$(PREFIX)" DESTDIR="$(DESTDIR)" install
install-sheepshaver: sheepshaver
	+$(MAKE) -C SheepShaver/src/Unix prefix="$(PREFIX)" DESTDIR="$(DESTDIR)" install
endif
endif

clean: clean-basilisk clean-sheepshaver


# Diagnose Homebrew without changing installed packages or shell configuration.
# Inspect flag separation without running configure or the emulator builders.
# No linker is invoked by this diagnostic.
linker-info:
	@printf 'Target LDFLAGS: %s\nHost LDFLAGS: %s\n' '$(LDFLAGS)' '$(HOST_LDFLAGS)'
	@printf '%s\n' 'Xcode: MACEMUS_LDFLAGS for app linking; MACEMUS_HOST_LDFLAGS for CPU-generator links.'
	@printf '%s\n' 'Unix: target LDFLAGS for emulator; HOST_LDFLAGS for executable generators.'
	@printf '%s\n' 'SDL2 dependency is selected by MACEMUS_SDL2_LINKAGE; inspect with make homebrew-info.'

test-linker-flags:
	@./tests/test-linker-flags.sh

# Test Xcode argument routing and the framework directory existence guard.
test-homebrew-frameworks:
	@./tests/test-homebrew-frameworks.sh

test-sdl2-linkage:
	@./tests/test-sdl2-linkage.sh

test-native-xcode:
	@./tests/test-native-xcode.sh

test-sheepshaver-startup:
	@CXX="$(CXX)" ./tests/test-sheepshaver-startup.sh

test-sheepshaver-app-logging:
	@./tests/test-sheepshaver-app-logging.sh

test-sheepshaver-configuration:
	@CXX="$(CXX)" ./tests/test-sheepshaver-configuration.sh

test-sheepshaver-boot-debugger:
	@CC="$(CC)" sh ./tests/test-sheepshaver-boot-debugger.sh

# Experimental PPC32 guest MMU only; does NOT activate Mac OS 9.2 boot.
test-sheepshaver-92-mmu:
	@CXX="$(CXX)" ./tests/test-sheepshaver-92-mmu.sh

test-sheepshaver-92-registers:
	@CXX="$(CXX)" ./tests/test-sheepshaver-92-registers.sh

# Ensure the active Xcode CPU archive contains the real PPC32 MMU object.
test-sheepshaver-mmu-link:
	@CXX="$(CXX)" sh ./tests/test-sheepshaver-mmu-link.sh

# Ensure the legacy Kheperix CPU register layout is preserved.
test-sheepshaver-register-layout:
	@CXX="$(CXX)" ./tests/test-sheepshaver-register-layout.sh

test-sheepshaver-rom-verification:
	@CXX="$(CXX)" ./tests/test-sheepshaver-rom-verification.sh

# Inspect an actual ROM file without SDL, the Cocoa GUI or guest execution.
check-sheepshaver-rom:
	@CXX="$(CXX)" SHEEPSHAVER_ROM="$(SHEEPSHAVER_ROM)" ./tests/check-sheepshaver-rom.sh

ifeq ($(MACEMUS_PLATFORM),macos)
sheepshaver-settings: sheepshaver
	@"$(MACEMUS_SHEEPSHAVER_APP)/Contents/MacOS/SheepShaver" --settings
else
sheepshaver-settings:
	@printf '%s\n' 'SheepShaver Cocoa settings require macOS.' >&2
	@exit 1
endif

native-info:
	@printf 'Native host architecture: %s\nNative CPU target: %s\n' '$(MACEMUS_HOST_ARCH)' '$(MACEMUS_BASILISK_CPU_TARGET)'

# This is an active macOS symbol/architecture/link probe, not a dry run.
# SDL3 is a runtime implementation dependency of sdl2-compat; do not add
# -lSDL3 to SDL2 callers unless a separate direct SDL3 API is used.
MACEMUS_SDL2_TEST_ARCH ?= $(MACEMUS_HOST_ARCH)
SDL2_EXPECT_EXPORTS ?=
# Avoid adding SDL extension libraries without source-symbol evidence.
audit-sdl-addons:
	@./tests/audit-sdl-addons.sh

check-sdl2-exports:
	@./tests/check-sdl2-exports.sh "$(MACEMUS_SDL2_SELECTED)" "$(MACEMUS_SDL2_LIBRARY_DIR)" "$(MACEMUS_SDL2_INCLUDE_FLAT)" "$(MACEMUS_SDL2_TEST_ARCH)" "$(SDL2_EXPECT_EXPORTS)"

# The portable Mac clipboard size/range checks are compiled with conversion
# warnings enabled and treated as errors, independent of the emulator.
test-type-conversions:
	@CXX="$(CXX)" ./tests/test-type-conversions.sh

cppflags-info:
	@printf 'Target CPPFLAGS: %s\nHost CPPFLAGS: %s\n' '$(CPPFLAGS)' '$(HOST_CPPFLAGS)'
	@printf '%s\n' 'Xcode: MACEMUS_CPPFLAGS for target compilation; MACEMUS_HOST_CPPFLAGS for CPU generators.'
	@printf '%s\n' 'Unix: CPPFLAGS on configure; project include paths are retained by generated Makefiles.'

homebrew-info:
ifeq ($(MACEMUS_PLATFORM),macos)
	@printf 'Homebrew mode: %s\nHost architecture: %s\n' '$(MACEMUS_HOMEBREW)' '$(MACEMUS_HOST_ARCH)'
	@printf 'Homebrew command: %s\nHomebrew prefix: %s\n' '$(MACEMUS_BREW)' '$(MACEMUS_BREW_PREFIX)'
	@printf 'Common bin: %s\nCommon include: %s\nCommon lib: %s\n' '$(MACEMUS_BREW_BIN)' '$(MACEMUS_BREW_INCLUDE)' '$(MACEMUS_BREW_LIB)'
	@printf 'Common frameworks: %s\n' '$(MACEMUS_BREW_FRAMEWORKS)'
	@if test -n '$(MACEMUS_BREW_FRAMEWORKS)' && test -d '$(MACEMUS_BREW_FRAMEWORKS)/SDL2.framework'; then \
		printf '%s\n' 'SDL2.framework in Homebrew frameworks: yes'; \
	else \
		printf '%s\n' 'SDL2.framework in Homebrew frameworks: not found'; \
	fi
	@printf 'SDL2 include root (<SDL2/SDL.h>): %s\n' '$(MACEMUS_SDL2_INCLUDE_ROOT)'
	@printf 'SDL2 flat include (<SDL.h>): %s\n' '$(MACEMUS_SDL2_INCLUDE_FLAT)'
	@printf 'GMP fallback: %s\nMPFR fallback: %s\n' '$(MACEMUS_GMP_PREFIX)' '$(MACEMUS_MPFR_PREFIX)'
	@printf 'SDL2 formula: %s\n' '$(MACEMUS_SDL2_PREFIX)'
	@printf 'SDL2 link mode: %s\nSDL2 library directory: %s\n' '$(MACEMUS_SDL2_SELECTED)' '$(MACEMUS_SDL2_LIBRARY_DIR)'
	@printf '%s\n' 'Note: SDL2.framework remains a separate Xcode dependency.'
else
	@printf '%s\n' 'Homebrew discovery is enabled for macOS Xcode builds only.'
endif

help:
	@printf '%s\n' \
		'MacEMUs top-level targets:' \
		'  make all                 Build Basilisk II and SheepShaver (default)' \
		'  make basilisk            Build Basilisk II only' \
		'  make sheepshaver         Build SheepShaver only' \
		'  make clean               Clean both emulator builds' \
		'  make install             Install both emulators' \
		'  make install             Reinstall existing macOS app bundles by default' \
		'  make install-basilisk    Install Basilisk II' \
		'  make install-sheepshaver Install SheepShaver' \
		'  make install-info        Show destination and bundle paths' \
		'  make test-install        Verify staging behavior' \
		'  make homebrew-info       Show discovered Homebrew dependencies' \
		'  make test-homebrew-frameworks  Verify framework search paths' \
		'  make test-sdl2-linkage   Check SDL2 library/framework selection' \
		'  make test-native-xcode   Check native Xcode target selection' \
		'  make test-sheepshaver-startup  Check ROM and RAM startup limits' \
		'  make test-sheepshaver-app-logging  Verify failure-stage tracing' \
		'  make test-sheepshaver-configuration  Test ROM/configuration routing' \
		'  make test-sheepshaver-boot-debugger  Check default Cocoa debugger wiring' \
		'  make test-sheepshaver-92-mmu  Check experimental PPC32 MMU translations' \
		'  make test-sheepshaver-92-registers  Test PPC MMU supervisor registers' \
		'  make test-sheepshaver-mmu-link Verify PPC32 reset symbol and Xcode CPU sources' \
		'  make test-sheepshaver-register-layout  Check legacy PPC register ABI' \
		'  make test-sheepshaver-rom-verification  Verify CHRP and ROM identity' \
		'  make check-sheepshaver-rom  Inspect a ROM without launching SheepShaver' \
		'  make sheepshaver-settings  Open Cocoa settings without ROM boot' \
		'  make native-info         Show host architecture and CPU target' \
		'  make check-sdl2-exports Verify SDL2 exports, architecture and link' \
		'  make audit-sdl-addons   Report use of optional SDL2 libraries' \
		'  make cppflags-info       Audit target/host CPPFLAGS routing' \
		'  make linker-info         Audit target/host LDFLAGS routing' \
		'  make test-linker-flags   Run non-Xcode linker flag smoke tests' \
		'  make test-type-conversions  Check clipboard narrowing boundaries' \
		'  make clean-basilisk      Clean Basilisk II only' \
		'  make clean-sheepshaver   Clean SheepShaver only' \
		'' \
		'Options: MACEMUS_PLATFORM=macos|unix|mingw (auto-detected), CONFIGURATION=Release,' \
		'         BUILD_ROOT=<path>, XCODE_ARGS=<arguments>,' \
		'         PREFIX=/usr/local, DESTDIR=<absolute staging root>,' \
		'         INSTALL_FLAGS=-f (default), INSTALL_FLAGS= (refuse overwrite),' \
		'         MACEMUS_BASILISK_APP=<path>, MACEMUS_SHEEPSHAVER_APP=<path>,' \
		'         CONFIGURE_ARGS=<arguments> (only on first Autotools configure)' \
		'         MACEMUS_HOMEBREW=auto|off|required, MACEMUS_BREW=<brew path>' \
		'         CPPFLAGS=<preprocessor options>, HOST_CPPFLAGS=<host-generator options>,' \
		'         LDFLAGS=<target-linker options>, HOST_LDFLAGS=<host-generator options>,' \
		'         MACEMUS_BREW_FRAMEWORKS=<framework directory>,' \
		'         MACEMUS_SDL2_LINKAGE=auto|dylib|framework, MACEMUS_SDL2_LIBRARY_DIR=<dir>,' \
		'         MACEMUS_SDL2_TEST_ARCH=arm64|x86_64, SDL2_EXPECT_EXPORTS=<symbols>'
