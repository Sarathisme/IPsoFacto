#!/bin/sh
# Run the IPsoFacto unit tests.
#
# Why this wrapper exists: on a Command-Line-Tools-only machine, a bare
# `swift test` fails with "no such module 'Testing'". CLT *does* carry
# Testing.framework and lib_TestingInterop.dylib, just not on the default
# framework/rpath search paths -- adding them explicitly makes swift-testing
# work under plain SwiftPM. Adapted from Codelight/Scripts/run-tests.sh.
#
# On a machine with a full Xcode install (e.g. GitHub Actions' macos-latest
# runner), Testing.framework lives at a different path and `swift test`
# already finds it unaided, so this script falls back to a plain `swift
# test` there instead of erroring out.
set -e

FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
INTEROP_LIB="$(xcode-select -p)/Library/Developer/usr/lib"

cd "$(dirname "$0")/.."

if [ -d "$FRAMEWORKS/Testing.framework" ]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -F -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$INTEROP_LIB" \
        "$@"
else
    exec swift test "$@"
fi
