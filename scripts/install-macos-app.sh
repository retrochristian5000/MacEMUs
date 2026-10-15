#!/bin/sh
# Copy built macOS applications, with opt-in -f replacement and rollback.
set -eu
fail() { printf 'MacEMUs install: %s\n' "$*" >&2; exit 1; }
force=0
if [ "${1:-}" = '-f' ]; then force=1; shift; fi
[ "$#" -ge 3 ] || fail 'expected [-f] DESTDIR PREFIX and at least one .app bundle'
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
# Never delete a previous install before checking every source.
for app do
    case "$app" in *.app) ;; *) fail "not a .app bundle: $app" ;; esac
    [ -f "$app/Contents/Info.plist" ] || fail "missing built bundle: $app"
    name=${app##*/}
    if [ -e "$dir/$name" ] || [ -L "$dir/$name" ]; then
        [ "$force" -eq 1 ] || fail "refusing to overwrite: $dir/$name (use INSTALL_FLAGS=-f)"
    fi
done
install -d "$dir" || fail "cannot create $dir"
work=$(mktemp -d "$dir/.macemu-install.XXXXXXXX") || fail "cannot stage bundles in $dir"
completed=0
restore() {
    code=$?
    trap - 0 1 2 3 15
    keep=0
    if [ "$completed" -ne 1 ]; then
        for app do
            name=${app##*/}
            target="$dir/$name"
            old="$work/old/$name"
            if [ -e "$old" ] || [ -L "$old" ]; then
                if [ -e "$target" ] || [ -L "$target" ]; then
                    rm -rf "$target" || keep=1
                fi
                if [ "$keep" -eq 0 ]; then
                    mv "$old" "$target" || keep=1
                fi
            elif [ -e "$work/placed/$name" ]; then
                if [ -e "$target" ] || [ -L "$target" ]; then
                    rm -rf "$target" || keep=1
                fi
            fi
        done
    fi
    if [ "$keep" -eq 0 ]; then
        rm -rf "$work" || :
    else
        printf 'MacEMUs install: rollback incomplete, preserved backup in %s\n' "$work" >&2
    fi
    exit "$code"
}
trap 'restore "$@"' 0
trap 'exit 1' 1 2 3 15
mkdir "$work/new" "$work/old" "$work/placed" || fail 'cannot initialize install staging'
# Complete each potentially failing copy before moving any installed app.
for app do
    name=${app##*/}
    if command -v ditto >/dev/null 2>&1; then
        ditto "$app" "$work/new/$name" || fail "copy failed: $app"
    else
        cp -R "$app" "$work/new/$name" || fail "copy failed: $app"
    fi
done
# Once all new apps are staged, back up the old ones and replace by rename.
for app do
    name=${app##*/}
    target="$dir/$name"
    if [ -e "$target" ] || [ -L "$target" ]; then
        [ "$force" -eq 1 ] || fail "refusing to overwrite: $target"
        mv "$target" "$work/old/$name" || fail "cannot back up $target"
    fi
done
for app do
    name=${app##*/}
    touch "$work/placed/$name" || fail 'cannot track install state'
    mv "$work/new/$name" "$dir/$name" || fail "cannot install $name"
    printf 'Installed: %s\n' "$dir/$name"
done
completed=1
