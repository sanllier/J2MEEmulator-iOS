#!/bin/bash
# Build j2me_api.jar — minimal J2ME API for iOS/miniJVM
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Output dir doubles as the source of truth for minijvm_rt.jar — once the
# runtime has been built into the iOS bundle's Resources/jars, reuse it
# from there so we don't depend on the miniJVM repo sitting next to us.
OUTPUT_DIR="$SCRIPT_DIR/../J2MEEmulator/Resources/jars"
MINIJVM_RT="$OUTPUT_DIR/minijvm_rt.jar"

# macOS ships a /usr/bin/javac stub that exits with an error when no JDK is
# installed — `command -v javac` succeeds against the stub, so we must
# actually try to run it before trusting the PATH.
if ! javac -version &> /dev/null; then
    if [ -f /opt/homebrew/opt/openjdk/bin/javac ]; then
        export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
    else
        echo "ERROR: working javac not found"; exit 1
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
