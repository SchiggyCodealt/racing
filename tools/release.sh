#!/usr/bin/env bash
# release.sh: build the Windows zip of a version from a clean copy of the project.
# ------------------------------------------------------------------
#   tools/release.sh 6.22.0            -> build/TrackRush-6.21.0-windows.zip
#   GODOT=/path/to/godot tools/release.sh 6.22.0
# Copies the files git knows (tracked, and new ones not ignored) as they are in the working tree to
# a temporary folder, imports them from scratch (no stale .godot cache), exports the "Windows
# Desktop" preset and zips TrackRush.exe, the training library next to it and docs/windows-readme.txt
# (as README.txt). Needs the 4.7.2 export templates. The version in project.godot and
# export_presets.cfg is not changed here: bump it first.
set -euo pipefail
ver="${1:?usage: tools/release.sh <version>}"
godot="${GODOT:-godot}"
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
grep -q "config/version=\"$ver\"" "$root/project.godot" || { echo "project.godot is not at version $ver" >&2; exit 1; }
(cd "$root" && git ls-files -co --exclude-standard -z | tar --null -T - -cf - 2>/dev/null) | tar -xf - -C "$work"
mkdir -p "$work/build/windows"
"$godot" --headless --path "$work" --import >"$work/import.log" 2>&1 || true
"$godot" --headless --path "$work" --import >>"$work/import.log" 2>&1 || true
"$godot" --headless --path "$work" --export-release "Windows Desktop" "$work/build/windows/TrackRush.exe" >"$work/export.log" 2>&1 || { tail -20 "$work/export.log" >&2; exit 1; }
if grep -E "^(ERROR|SCRIPT ERROR)" "$work/export.log" | grep -v "export_presets\|RID\|leaked" >&2; then
	echo "the export printed errors (above)" >&2
	exit 1
fi
dll="libtrackrush.windows.template_release.x86_64.dll"
test -s "$work/build/windows/TrackRush.exe" && test -s "$work/build/windows/$dll" || { echo "the export did not write TrackRush.exe and $dll" >&2; tail -20 "$work/export.log" >&2; exit 1; }
cp "$root/docs/windows-readme.txt" "$work/build/windows/README.txt"
grep -q "Track Rush $ver " "$work/build/windows/README.txt" || { echo "docs/windows-readme.txt is not for version $ver" >&2; exit 1; }
mkdir -p "$root/build"
out="$root/build/TrackRush-$ver-windows.zip"
rm -f "$out"
(cd "$work/build/windows" && zip -q -X "$out" README.txt "$dll" TrackRush.exe)
ls -la "$out"
