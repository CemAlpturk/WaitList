#!/bin/bash
# Assembles WaitList.app from the SwiftPM build output. No Xcode required for the default build.
#   Packaging/build-app.sh [debug|release]
#   UNIVERSAL=1 Packaging/build-app.sh release    # arm64 + x86_64 in one binary (needs Xcode)
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

BUILD_FLAGS=(-c "$CONFIG" --package-path "$ROOT")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  # Multiple --arch flags make SwiftPM build through Xcode's build system into a different folder;
  # --show-bin-path below gets the same flags so it finds that folder.
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

# Hide the harmless "search path" linker warnings, but never hide a failed build: with pipefail the
# pipeline's status is swift build's when it fails (the filter itself always succeeds).
BUILD_STATUS=0
swift build "${BUILD_FLAGS[@]}" 2>&1 | { grep -v "warning: search path" || true; } || BUILD_STATUS=$?
if (( BUILD_STATUS != 0 )); then
  echo "error: swift build failed (exit $BUILD_STATUS); no app was assembled" >&2
  exit "$BUILD_STATUS"
fi
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
[[ -x "$BIN_DIR/$NAME" ]] || { echo "error: build failed, no binary at $BIN_DIR/$NAME" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$NAME" "$APP/Contents/MacOS/$NAME"
cp "$PLIST" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Runtime resources: the app icon and the menubar glyphs.
if compgen -G "$ROOT/Resources/*" > /dev/null; then
  cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
fi

# Ad-hoc signature: enough for local use and notifications. Not notarized.
codesign --force --sign - --identifier "com.cemalpturk.WaitList" "$APP"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/$NAME" 2>/dev/null || echo unknown)"
echo "Built $APP ($CONFIG, v$PLIST_VERSION, $ARCHS)"
