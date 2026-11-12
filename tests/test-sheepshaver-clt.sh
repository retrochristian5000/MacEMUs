#!/bin/sh
# Exercise the Make dependency graph and bundle assembly without a macOS SDK.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sheepshaver-clt.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
export CLT_TEST_ROOT="$tmp"
mkdir "$tmp/sdk" "$tmp/lib"
touch "$tmp/lib/libSDL2.dylib"

cat > "$tmp/xcrun" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$CLT_TEST_ROOT/tool-log"
if [ "$3" = --show-sdk-path ]; then
    printf '%s\n' "$CLT_TEST_ROOT/sdk"
    exit
fi
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output=$2; shift ;;
        -MF) depfile=$2; shift ;;
    esac
    shift
done
printf '%s\n' '#!/bin/sh' 'exit 0' > "$output"
chmod +x "$output"
if [ -n "${depfile:-}" ]; then
    touch "$depfile"
fi
EOF
cat > "$tmp/plutil" <<'EOF'
#!/bin/sh
set -eu
test "$1" = -lint
grep -F '<string>net.cebix.sheepshaver</string>' "$2" >/dev/null
if grep -F '$(' "$2"; then
    exit 1
fi
EOF
cat > "$tmp/codesign" <<'EOF'
#!/bin/sh
set -eu
for arg do bundle=$arg; done
test -x "$bundle/Contents/MacOS/SheepShaver"
test -x "$bundle/Contents/Resources/etherhelpertool"
test -f "$bundle/Contents/Resources/English.lproj/VMSettingsWindow.nib/keyedobjects.nib"
EOF
chmod +x "$tmp/xcrun" "$tmp/plutil" "$tmp/codesign"

run_make() {
    make --no-print-directory MACEMUS_PLATFORM=macos MACEMUS_HOMEBREW=off \
        SHEEPSHAVER_MACOS_BUILD=clt XCRUN="$tmp/xcrun" XCODEBUILD=false \
        PLUTIL="$tmp/plutil" CODESIGN="$tmp/codesign" "$@"
}

root="$tmp/build output"
run_make -j4 sheepshaver BUILD_ROOT="$root" MACEMUS_HOST_ARCH=arm64 > "$tmp/arm-build"
app="$root/SheepShaver/CommandLineTools/Release/SheepShaver.app"
test -x "$app/Contents/MacOS/SheepShaver"
test -f "$app/Contents/Resources/SheepVM.icns"
grep -F -- '-framework SDL2' "$tmp/tool-log" >/dev/null
if grep -F -- '-pagezero_size' "$tmp/tool-log"; then
    exit 1
fi

# The CLT manifest should cover both source phases of the active Xcode app.
sed -n 's@.* /\* \([^ ]*\) in Sources \*/,.*@\1@p' \
    SheepShaver/src/MacOSX/SheepShaver_Xcode8.xcodeproj/project.pbxproj | sort > "$tmp/xcode-sources"
sed -n 's@.* -c SheepShaver/src/\([^ ]*\) -o .*@\1@p' "$tmp/tool-log" |
    sed 's@.*/@@' | sort > "$tmp/clt-sources"
diff -u "$tmp/xcode-sources" "$tmp/clt-sources"

: > "$tmp/tool-log"
run_make sheepshaver BUILD_ROOT="$root" MACEMUS_HOST_ARCH=arm64 > "$tmp/rebuild"
test "$(cat "$tmp/tool-log")" = '--sdk macosx --show-sdk-path'

run_make -j4 sheepshaver BUILD_ROOT="$root" MACEMUS_HOST_ARCH=arm64 \
    MACOSX_DEPLOYMENT_TARGET=13.0 > "$tmp/retarget"
grep -F '<string>13.0</string>' "$app/Contents/Info.plist" >/dev/null
grep -F -- '-mmacosx-version-min=13.0' "$tmp/tool-log" >/dev/null

run_make install-sheepshaver BUILD_ROOT="$root" MACEMUS_HOST_ARCH=arm64 \
    MACOSX_DEPLOYMENT_TARGET=13.0 DESTDIR="$tmp/install" PREFIX=/usr/local > "$tmp/install-log"
test -x "$tmp/install/usr/local/Applications/SheepShaver.app/Contents/MacOS/SheepShaver"

run_make -n sheepshaver BUILD_ROOT="$tmp/intel" MACEMUS_HOST_ARCH=x86_64 \
    MACEMUS_SDL2_LINKAGE=dylib MACEMUS_SDL2_LIBRARY_DIR="$tmp/lib" > "$tmp/intel-plan"
grep -F -- '-arch "x86_64"' "$tmp/intel-plan" >/dev/null
grep -F -- '-Wl,-pagezero_size,0x3000' "$tmp/intel-plan" >/dev/null
grep -F -- "\"$tmp/lib/libSDL2.dylib\"" "$tmp/intel-plan" >/dev/null

if run_make sheepshaver BUILD_ROOT="$tmp/no-sdk" MACEMUS_HOST_ARCH=arm64 \
    SDKROOT="$tmp/missing" > "$tmp/no-sdk-log" 2>&1; then
    exit 1
fi
grep -F 'macOS SDK unavailable' "$tmp/no-sdk-log" >/dev/null

run_make clean-sheepshaver BUILD_ROOT="$root" MACEMUS_HOST_ARCH=arm64 > "$tmp/clean"
test ! -e "$app"
printf '%s\n' 'SheepShaver Command Line Tools build graph and bundle: PASS'
