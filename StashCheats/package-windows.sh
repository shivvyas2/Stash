#!/bin/sh
# Packages the Vice City cheat codes for Windows players, who don't use Stash, as StashCheats-ViceCity-Windows.zip
# in the current folder: the plugin, Ultimate ASI Loader as dinput8.dll, its licence and a readme.
# Needs Zig like build.sh, and the GitHub CLI to download the loader.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(pwd)/StashCheats-ViceCity-Windows.zip"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/package/scripts"
"${ZIG:-zig}" cc -target x86-windows-gnu -O2 -shared -s -Wall -o "$work/package/scripts/StashCheatsVC.asi" \
    "$root/StashCheats/ViceCityCheats.c"
rm -f "$work/package/scripts/"*.lib    # import library Zig writes alongside; Windows players don't need it

gh release download Win32-latest -R ThirteenAG/Ultimate-ASI-Loader -p dinput8-Win32.zip -D "$work"
/usr/bin/unzip -q "$work/dinput8-Win32.zip" -d "$work/loader"
expected=$(sed -n 's/^Hash *: *//p' "$work/loader/dinput8-Win32.SHA512" | tr -d '\r' | tr 'A-F' 'a-f')
actual=$(shasum -a 512 "$work/loader/dinput8.dll" | cut -d' ' -f1)
[ "$expected" = "$actual" ] || { echo "dinput8.dll doesn't match its published SHA-512" >&2; exit 1; }
cp "$work/loader/dinput8.dll" "$work/package/"
gh api repos/ThirteenAG/Ultimate-ASI-Loader/license -q .content | base64 -d > "$work/package/LICENSE-UltimateASILoader.txt"

# Windows line endings so Notepad shows the readme properly
sed 's/$/\r/' "$root/StashCheats/README-Windows.txt" > "$work/package/README.txt"
rm -f "$out"
(cd "$work/package" && /usr/bin/zip -q -X -r "$out" .)
echo "Built $out"
