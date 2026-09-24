#!/bin/sh
# Run the IPsoFacto unit tests.
#
# Why this wrapper exists: a bare `swift test` fails on this machine with
# "no such module 'Testing'" (and likewise for XCTest). Both test libraries
# ship inside Xcode, and this machine has Command Line Tools only -- but CLT
# *does* carry Testing.framework and lib_TestingInterop.dylib, just not on
# the default framework/rpath search paths. Adding them explicitly makes
# swift-testing work under plain SwiftPM. Adapted from
# Codelight/Scripts/run-tests.sh.
#
# Re-check whether this is still needed if a full Xcode install appears.
set -e

FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
INTEROP_LIB="$(xcode-select -p)/Library/Developer/usr/lib"

if [ ! -d "$FRAMEWORKS/Testing.framework" ]; then
    echo "Testing.framework not found at $FRAMEWORKS -- is the active developer directory correct?" >&2
    exit 1
fi

cd "$(dirname "$0")/.."
exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$INTEROP_LIB" \
    "$@"
