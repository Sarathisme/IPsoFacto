#!/bin/sh
# Assemble, ad-hoc sign and install the IPso Facto.app bundle.
#
# Why this script exists: this machine has Command Line Tools only (no
# Xcode.app), so there is no Xcode project to produce a signed .app.
# `swift build` alone only produces a bare Mach-O executable with no
# Info.plist, so it cannot carry LSUIElement or register as a login item.
# This script builds the release binary, assembles a
# real .app bundle around it with Resources/Info.plist, ad-hoc signs it,
# and installs it to /Applications, which SMAppService's login-item
# registration expects a stable, standard location to run from.
set -e

cd "$(dirname "$0")/.."

APP_DISPLAY_NAME="IPso Facto"
EXECUTABLE_NAME="IPsoFacto"
BUILD_DIR=".build"
APP_BUNDLE_DIR="$BUILD_DIR/${EXECUTABLE_NAME}.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

echo "==> Building release binary for $APP_DISPLAY_NAME"
if swift build -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE_NAME"; then
    BINARY_PATH="$BUILD_DIR/apple/Products/Release/$EXECUTABLE_NAME"
else
    echo "WARNING: universal (arm64+x86_64) build failed on this toolchain." >&2
    echo "WARNING: falling back to a $(uname -m)-only release build." >&2
    echo "WARNING: the resulting .app will only run on $(uname -m) Macs -- NFR-5 (Intel support) is not met by this build." >&2
    swift build -c release --product "$EXECUTABLE_NAME"
    BINARY_PATH="$BUILD_DIR/release/$EXECUTABLE_NAME"
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: expected binary not found at $BINARY_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE_DIR"
rm -rf "$APP_BUNDLE_DIR"
mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS"
mkdir -p "$APP_BUNDLE_DIR/Contents/Resources"
cp "$BINARY_PATH" "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp Resources/Info.plist "$APP_BUNDLE_DIR/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_BUNDLE_DIR"
codesign --verify --verbose "$APP_BUNDLE_DIR"

echo "==> Installing to $INSTALL_DIR"
rm -rf "$INSTALL_DIR/${EXECUTABLE_NAME}.app"
cp -R "$APP_BUNDLE_DIR" "$INSTALL_DIR/"

echo "==> Done: $INSTALL_DIR/${EXECUTABLE_NAME}.app"
echo "Launch it with: open \"$INSTALL_DIR/${EXECUTABLE_NAME}.app\""
