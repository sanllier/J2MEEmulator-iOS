#!/bin/bash
# Build j2me_api.jar — minimal J2ME API for iOS/miniJVM
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MINIJVM_RT="$SCRIPT_DIR/../../miniJVM-2.0.0/binary/lib/minijvm_rt.jar"
OUTPUT_DIR="$SCRIPT_DIR/../J2MEEmulator/Resources/jars"

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

echo "Building j2me_api.jar..."

rm -rf "$SCRIPT_DIR/classes"
mkdir -p "$SCRIPT_DIR/classes"
mkdir -p "$OUTPUT_DIR"

find "$SCRIPT_DIR/src" -name "*.java" > "$SCRIPT_DIR/sources.txt"

javac --release 8 \
    -cp "$MINIJVM_RT" \
    -d "$SCRIPT_DIR/classes" \
    @"$SCRIPT_DIR/sources.txt"

jar cf "$OUTPUT_DIR/j2me_api.jar" -C "$SCRIPT_DIR/classes" .

rm -f "$SCRIPT_DIR/sources.txt"
echo "Built: $OUTPUT_DIR/j2me_api.jar"
