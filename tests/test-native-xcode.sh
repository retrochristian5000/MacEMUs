#!/bin/sh
# Dry-run both native host architectures; no Xcode installation required.
set -eu
cd "$(dirname "$0")/.."
fail() { printf 'native Xcode: %s\n' "$*" >&2; exit 1; }
for arch in arm64 x86_64; do
    case "$arch" in
        arm64) cpu=uae_cpu_arm64; other=uae_cpu_x86_64; proj=uae_cpu_2021.xcodeproj ;;
        x86_64) cpu=uae_cpu_x86_64; other=uae_cpu_arm64; proj=uae_cpu.xcodeproj ;;
    esac
    out=$(make -n --no-print-directory basilisk sheepshaver \
        MACEMUS_PLATFORM=macos MACEMUS_HOMEBREW=off \
        MACEMUS_HOST_ARCH="$arch" XCODE_ARGS='ARCHS=wrong') ||
        fail "build dry run failed ($arch)"
    commands=$(printf '%s\n' "$out" | awk '{
        if (sub(/[[:space:]]*\\$/, "")) { printf "%s ", $0; next }
        print
    }' | grep 'xcodebuild -project') || fail 'missing Xcode build commands'
    [ "$(printf '%s\n' "$commands" | wc -l | tr -d ' ')" = 3 ] ||
        fail "expected native CPU + 2 app commands ($arch)"
    printf '%s\n' "$commands" | grep -F -- "-project BasiliskII/src/MacOSX/$proj -target $cpu" >/dev/null ||
        fail "wrong CPU target ($arch)"
    if printf '%s\n' "$commands" | grep -F -- "-target $other" >/dev/null; then
        fail "cross-architecture CPU target built ($arch)"
    fi
    [ "$(printf '%s\n' "$commands" | grep -Fc "ARCHS=\"$arch\" ONLY_ACTIVE_ARCH=YES HOST_ARCH=\"$arch\"")" = 3 ] ||
        fail "native settings missing ($arch)"
    printf '%s\n' "$commands" | grep -F -- '-target BasiliskII' >/dev/null ||
        fail 'Basilisk II app omitted'
    printf '%s\n' "$commands" | grep -F -- '-target SheepShaver' >/dev/null ||
        fail 'SheepShaver app omitted'
    clean=$(make -n --no-print-directory clean-basilisk \
        MACEMUS_PLATFORM=macos MACEMUS_HOMEBREW=off MACEMUS_HOST_ARCH="$arch") ||
        fail "clean dry run failed ($arch)"
    printf '%s\n' "$clean" | grep -F -- "-target $cpu" >/dev/null ||
        fail "CPU archive not cleaned ($arch)"
    if printf '%s\n' "$clean" | grep -F -- "-target $other" >/dev/null; then
        fail "cross CPU cleaned ($arch)"
    fi
done
if make -n --no-print-directory basilisk MACEMUS_PLATFORM=macos \
    MACEMUS_HOMEBREW=off MACEMUS_HOST_ARCH=ppc64 >/dev/null 2>&1; then
    fail 'unsupported host accepted'
fi
printf '%s\n' 'native Xcode target routing: PASS'
