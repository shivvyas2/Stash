#!/bin/sh
# Builds the Vice City cheat plugin into the zip Stash installs, Stash/Resources/StashCheatsVC.zip.
# Needs Zig 0.13 (https://ziglang.org) for its 32-bit Windows C compiler: ZIG=/path/to/zig StashCheats/build.sh
# The zip is checked in, so Xcode builds don't need Zig.
set -e
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/scripts" Stash/Resources
"${ZIG:-zig}" cc -target x86-windows-gnu -O2 -shared -s -Wall -o "$work/scripts/StashCheatsVC.asi" StashCheats/ViceCityCheats.c
rm -f Stash/Resources/StashCheatsVC.zip
(cd "$work" && /usr/bin/zip -q -X -r - scripts/StashCheatsVC.asi) > Stash/Resources/StashCheatsVC.zip
echo "Built Stash/Resources/StashCheatsVC.zip"
