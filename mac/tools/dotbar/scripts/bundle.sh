#!/usr/bin/env bash
# Builds dotbar in release and wraps it in dotbar.app: Location Services only asks an app bundle with an identifier and a
# usage description (Resources/Info.plist) for the permission the weather box needs. LSUIElement keeps it out of the
# Dock. Signed ad hoc (no paid developer account): enough for the permission to stick to this build on this Mac.
#   scripts/bundle.sh            -> .build/dotbar.app (git-ignored)
#   scripts/bundle.sh <folder>   -> <folder>/dotbar.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/.build}"
APP="$OUT/dotbar.app"
BUILD_SECONDS=600 # a build that hangs is given up

/usr/bin/perl -e 'alarm shift; exec @ARGV' "$BUILD_SECONDS" swift build -c release --package-path "$ROOT" --product dotbar
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/dotbar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/dotbar"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign -s - --force --identifier dev.dotfiles.dotbar "$APP"
codesign --verify "$APP"
echo "$APP"
