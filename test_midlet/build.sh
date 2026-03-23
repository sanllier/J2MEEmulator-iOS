#!/bin/bash
# Build test_midlet.jar — Test MIDlet for J2ME Emulator
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MINIJVM_RT="$SCRIPT_DIR/../../miniJVM-2.0.0/binary/lib/minijvm_rt.jar"
J2ME_API="$SCRIPT_DIR/../J2MEEmulator/Resources/jars/j2me_api.jar"
OUTPUT_DIR="$SCRIPT_DIR/../J2MEEmulator/Resources/apps"

if ! command -v javac &> /dev/null; then
    if [ -f /opt/homebrew/opt/openjdk/bin/javac ]; then
        export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
    else
        echo "ERROR: javac not found"; exit 1
    fi
fi

if [ ! -f "$MINIJVM_RT" ]; then
    echo "ERROR: minijvm_rt.jar not found at $MINIJVM_RT"
    exit 1
fi

if [ ! -f "$J2ME_API" ]; then
    echo "ERROR: j2me_api.jar not found at $J2ME_API"
    echo "Run j2me_api/build.sh first"
    exit 1
fi

echo "Building test_midlet.jar..."

rm -rf "$SCRIPT_DIR/classes"
mkdir -p "$SCRIPT_DIR/classes"
mkdir -p "$OUTPUT_DIR"

javac --release 8 \
    -cp "$MINIJVM_RT:$J2ME_API" \
    -d "$SCRIPT_DIR/classes" \
    "$SCRIPT_DIR/src/TestMIDlet.java"

jar cfm "$OUTPUT_DIR/test_midlet.jar" "$SCRIPT_DIR/MANIFEST.MF" -C "$SCRIPT_DIR/classes" .

echo "Built: $OUTPUT_DIR/test_midlet.jar"
