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

.PHONY: all basilisk sheepshaver clean clean-basilisk clean-sheepshaver help

all: basilisk sheepshaver

ifeq ($(MACEMUS_PLATFORM),macos)
basilisk:
	$(XCODEBUILD) -project BasiliskII/src/MacOSX/BasiliskII.xcodeproj -target BasiliskII \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/BasiliskII" \
		OBJROOT="$(BUILD_ROOT)/BasiliskII/obj" $(XCODE_ARGS) build

sheepshaver:
	$(XCODEBUILD) -project SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj -target SheepShaver \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/SheepShaver" \
		OBJROOT="$(BUILD_ROOT)/SheepShaver/obj" $(XCODE_ARGS) build

clean-basilisk:
	$(XCODEBUILD) -project BasiliskII/src/MacOSX/BasiliskII.xcodeproj -target BasiliskII \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/BasiliskII" \
		OBJROOT="$(BUILD_ROOT)/BasiliskII/obj" $(XCODE_ARGS) clean

clean-sheepshaver:
	$(XCODEBUILD) -project SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj -target SheepShaver \
		-configuration $(CONFIGURATION) \
		SYMROOT="$(BUILD_ROOT)/SheepShaver" \
		OBJROOT="$(BUILD_ROOT)/SheepShaver/obj" $(XCODE_ARGS) clean

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

help:
	@printf '%s\n' \
		'MacEMUs top-level targets:' \
		'  make all                 Build Basilisk II and SheepShaver (default)' \
		'  make basilisk            Build Basilisk II only' \
		'  make sheepshaver         Build SheepShaver only' \
		'  make clean               Clean both emulator builds' \
		'  make clean-basilisk      Clean Basilisk II only' \
		'  make clean-sheepshaver   Clean SheepShaver only' \
		'' \
		'Options: MACEMUS_PLATFORM=macos|unix|mingw (auto-detected), CONFIGURATION=Release,' \
		'         BUILD_ROOT=<path>, XCODE_ARGS=<arguments>,' \
		'         CONFIGURE_ARGS=<arguments> (only on first Autotools configure)'
