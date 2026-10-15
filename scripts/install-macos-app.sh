#!/bin/sh
# Copy one or more already-built .app bundles, optionally to a staging root.
set -eu
fail() { printf 'MacEMUs install: %s\n' "$*" >&2; exit 1; }
[ "$#" -ge 3 ] || fail 'expected DESTDIR PREFIX and at least one .app bundle'
stage=$1
prefix=$2
shift 2
case "$prefix" in /*) ;; *) fail "PREFIX must be absolute: $prefix" ;; esac
case "$stage" in ''|/*) ;; *) fail "DESTDIR must be empty or absolute: $stage" ;; esac
for p in "$stage" "$prefix"; do
    case "$p" in */../*|*/..|*/./*|*/.) fail "dot segments in path: $p" ;; esac
done
while [ "$prefix" != / ] && [ "${prefix%/}" != "$prefix" ]; do prefix=${prefix%/}; done
while [ -n "$stage" ] && [ "${stage%/}" != "$stage" ]; do stage=${stage%/}; done
[ "$stage" != / ] || stage=
dir="$stage${prefix%/}/Applications"
# Validate all input and output paths before copying anything.
for app do
    case "$app" in *.app) ;; *) fail "not an .app bundle: $app" ;; esac
    [ -f "$app/Contents/Info.plist" ] || fail "missing built bundle: $app"
    name=${app##*/}
    if [ -e "$dir/$name" ] || [ -L "$dir/$name" ]; then
        fail "refusing to overwrite: $dir/$name"
    fi
done
install -d "$dir" || fail "cannot create $dir"
for app do
    name=${app##*/}
    if command -v ditto >/dev/null 2>&1; then
        ditto "$app" "$dir/$name" || fail "copy failed: $app"
    else
        cp -R "$app" "$dir/$name" || fail "copy failed: $app"
    fi
    printf 'Installed: %s\n' "$dir/$name"
done
