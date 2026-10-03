#!/bin/bash
# Assembles WaitList.app from the SwiftPM build output. No Xcode required.
#   Packaging/build-app.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
NAME="WaitList"
OUT="$ROOT/build"
APP="$OUT/$NAME.app"
PLIST="$ROOT/Packaging/Info.plist"

# Keep the version in Info.plist and in code in sync.
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
CODE_VERSION="$(sed -n 's/.*public static let version = "\(.*\)".*/\1/p' "$ROOT/Sources/WaitListCore/Version.swift")"
if [[ "$PLIST_VERSION" != "$CODE_VERSION" ]]; then
  echo "error: version mismatch: Info.plist=$PLIST_VERSION, Version.swift=$CODE_VERSION" >&2
  exit 1
fi

swift build -c "$CONFIG" --package-path "$ROOT" 2>&1 | grep -v "warning: search path" || true
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
[[ -x "$BIN_DIR/$NAME" ]] || { echo "error: build failed, no binary at $BIN_DIR/$NAME" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$NAME" "$APP/Contents/MacOS/$NAME"
cp "$PLIST" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Runtime resources: app icon, menubar glyphs, notification image.
if compgen -G "$ROOT/Resources/*" > /dev/null; then
  cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
fi

# Ad-hoc signature: enough for local use and notifications. Not notarized.
codesign --force --sign - --identifier "com.cemalpturk.WaitList" "$APP"

echo "Built $APP ($CONFIG, v$PLIST_VERSION)"
