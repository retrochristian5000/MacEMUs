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
# SDL2 discovery is diagnostic only; the active Xcode projects still embed a framework.
MACEMUS_SDL2_PREFIX ?= $(shell \
	if test -n "$(MACEMUS_BREW)" && test -n "$(MACEMUS_BREW_PREFIX)"; then \
		"$(MACEMUS_BREW)" --prefix --installed sdl2-compat 2>/dev/null || \
		"$(MACEMUS_BREW)" --prefix --installed sdl2 2>/dev/null || :; \
	fi)
ifneq ($(strip $(MACEMUS_BREW_PREFIX)),)
MACEMUS_BREW_BIN := $(MACEMUS_BREW_PREFIX)/bin
MACEMUS_BREW_INCLUDE := $(MACEMUS_BREW_PREFIX)/include
MACEMUS_BREW_LIB := $(MACEMUS_BREW_PREFIX)/lib
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

.PHONY: all basilisk sheepshaver clean clean-basilisk clean-sheepshaver help homebrew-info cppflags-info linker-info test-linker-flags

all: basilisk sheepshaver

ifeq ($(MACEMUS_PLATFORM),macos)
basilisk:
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project BasiliskII/src/MacOSX/BasiliskII.xcodeproj -target BasiliskII \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/BasiliskII" \
		OBJROOT="$(BUILD_ROOT)/BasiliskII/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(XCODE_ARGS) build

sheepshaver:
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj -target SheepShaver \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/SheepShaver" \
		OBJROOT="$(BUILD_ROOT)/SheepShaver/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(XCODE_ARGS) build

clean-basilisk:
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project BasiliskII/src/MacOSX/BasiliskII.xcodeproj -target BasiliskII \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/BasiliskII" \
		OBJROOT="$(BUILD_ROOT)/BasiliskII/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(XCODE_ARGS) clean

clean-sheepshaver:
	$(MACEMUS_XCODE_ENV) $(XCODEBUILD) -project SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj -target SheepShaver \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/SheepShaver" \
		OBJROOT="$(BUILD_ROOT)/SheepShaver/obj" $(MACEMUS_XCODE_BREW_ARGS) $(MACEMUS_XCODE_CPP_ARGS) $(MACEMUS_XCODE_LINK_ARGS) $(XCODE_ARGS) clean

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

clean: clean-basilisk clean-sheepshaver


# Diagnose Homebrew without changing installed packages or shell configuration.
# Inspect flag separation without running configure or the emulator builders.
# No linker is invoked by this diagnostic.
linker-info:
	@printf 'Target LDFLAGS: %s\nHost LDFLAGS: %s\n' '$(LDFLAGS)' '$(HOST_LDFLAGS)'
	@printf '%s\n' 'Xcode: MACEMUS_LDFLAGS for app linking; MACEMUS_HOST_LDFLAGS for CPU-generator links.'
	@printf '%s\n' 'Unix: target LDFLAGS for emulator; HOST_LDFLAGS for executable generators.'
	@printf '%s\n' 'SDL2.framework linkage remains configured separately from Homebrew SDL2 headers.'

test-linker-flags:
	@./tests/test-linker-flags.sh

cppflags-info:
	@printf 'Target CPPFLAGS: %s\nHost CPPFLAGS: %s\n' '$(CPPFLAGS)' '$(HOST_CPPFLAGS)'
	@printf '%s\n' 'Xcode: MACEMUS_CPPFLAGS for target compilation; MACEMUS_HOST_CPPFLAGS for CPU generators.'
	@printf '%s\n' 'Unix: CPPFLAGS on configure; project include paths are retained by generated Makefiles.'

homebrew-info:
ifeq ($(MACEMUS_PLATFORM),macos)
	@printf 'Homebrew mode: %s\nHost architecture: %s\n' '$(MACEMUS_HOMEBREW)' '$(MACEMUS_HOST_ARCH)'
	@printf 'Homebrew command: %s\nHomebrew prefix: %s\n' '$(MACEMUS_BREW)' '$(MACEMUS_BREW_PREFIX)'
	@printf 'Common bin: %s\nCommon include: %s\nCommon lib: %s\n' '$(MACEMUS_BREW_BIN)' '$(MACEMUS_BREW_INCLUDE)' '$(MACEMUS_BREW_LIB)'
	@printf 'SDL2 include root (<SDL2/SDL.h>): %s\n' '$(MACEMUS_SDL2_INCLUDE_ROOT)'
	@printf 'SDL2 flat include (<SDL.h>): %s\n' '$(MACEMUS_SDL2_INCLUDE_FLAT)'
	@printf 'GMP fallback: %s\nMPFR fallback: %s\n' '$(MACEMUS_GMP_PREFIX)' '$(MACEMUS_MPFR_PREFIX)'
	@printf 'SDL2 formula: %s\n' '$(MACEMUS_SDL2_PREFIX)'
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
		'  make homebrew-info       Show discovered Homebrew dependencies' \
		'  make cppflags-info       Audit target/host CPPFLAGS routing' \
		'  make linker-info         Audit target/host LDFLAGS routing' \
		'  make test-linker-flags   Run non-Xcode linker flag smoke tests' \
		'  make clean-basilisk      Clean Basilisk II only' \
		'  make clean-sheepshaver   Clean SheepShaver only' \
		'' \
		'Options: MACEMUS_PLATFORM=macos|unix|mingw (auto-detected), CONFIGURATION=Release,' \
		'         BUILD_ROOT=<path>, XCODE_ARGS=<arguments>,' \
		'         CONFIGURE_ARGS=<arguments> (only on first Autotools configure)' \
		'         MACEMUS_HOMEBREW=auto|off|required, MACEMUS_BREW=<brew path>' \
		'         CPPFLAGS=<preprocessor options>, HOST_CPPFLAGS=<host-generator options>,' \
		'         LDFLAGS=<target-linker options>, HOST_LDFLAGS=<host-generator options>'
