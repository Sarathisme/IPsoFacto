#!/bin/sh
# Assemble, ad-hoc sign and package a distributable IPso Facto.app.
#
# Why this script exists: Scripts/build-app.sh builds and installs straight
# to /Applications for local development. This script produces the same
# signed .app as a standalone artifact under dist/, plus a zip archive
# suitable for handing to someone else or attaching to a GitHub release --
# without touching /Applications on this machine.
set -e

cd "$(dirname "$0")/.."

APP_DISPLAY_NAME="IPso Facto"
EXECUTABLE_NAME="IPsoFacto"
BUILD_DIR=".build"
DIST_DIR="dist"
APP_BUNDLE_DIR="$DIST_DIR/${EXECUTABLE_NAME}.app"

echo "==> Building release binary for $APP_DISPLAY_NAME"
if swift build -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE_NAME"; then
    BINARY_PATH="$BUILD_DIR/apple/Products/Release/$EXECUTABLE_NAME"
else
    echo "WARNING: universal (arm64+x86_64) build failed on this toolchain." >&2
    echo "WARNING: falling back to a $(uname -m)-only release build." >&2
    echo "WARNING: the resulting .app will only run on $(uname -m) Macs -- Intel support is not met by this build." >&2
    swift build -c release --product "$EXECUTABLE_NAME"
    BINARY_PATH="$BUILD_DIR/release/$EXECUTABLE_NAME"
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: expected binary not found at $BINARY_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE_DIR"
mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE_DIR"
mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS"
mkdir -p "$APP_BUNDLE_DIR/Contents/Resources"
cp "$BINARY_PATH" "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp Resources/Info.plist "$APP_BUNDLE_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE_DIR/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_BUNDLE_DIR"
codesign --verify --verbose "$APP_BUNDLE_DIR"

echo "==> Zipping for distribution"
ZIP_PATH="$DIST_DIR/${EXECUTABLE_NAME}.zip"
rm -f "$ZIP_PATH"
(cd "$DIST_DIR" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${EXECUTABLE_NAME}.app" "$(basename "$ZIP_PATH")")

echo "==> Done:"
echo "  $APP_BUNDLE_DIR"
echo "  $ZIP_PATH"
echo
echo "NOTE: this build is ad-hoc signed, not notarized. Anyone else opening"
echo "it will need to right-click > Open (or clear the quarantine flag) past"
echo "Gatekeeper's 'unidentified developer' warning the first time."
