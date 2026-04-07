#!/bin/bash
# Build Pucks and install to /Applications/Pucks.app
# Permissions persist across rebuilds because the bundle ID + signing stay the same.

set -e

echo "Building..."
cd "$(dirname "$0")"
swift build 2>&1 | tail -3

# Kill existing instance
pkill -f "Pucks.app/Contents/MacOS/Pucks" 2>/dev/null || true
sleep 0.5

APP_DIR="/Applications/Pucks.app/Contents"
MACOS_DIR="$APP_DIR/MacOS"
RES_DIR="$APP_DIR/Resources"

# Create app bundle structure if needed
mkdir -p "$MACOS_DIR" "$RES_DIR"

# Copy binary (SPM output name matches target name)
cp .build/debug/Pucks "$MACOS_DIR/Pucks"

# Copy Info.plist
cp Pucks/Info.plist "$APP_DIR/Info.plist"

# Copy entitlements (used for signing)
cp Pucks/Pucks.entitlements /tmp/Pucks.entitlements

# Copy resources (icon, sounds, etc)
cp Pucks/Resources/* "$RES_DIR/" 2>/dev/null || true

# Codesign with dev identity — NO hardened runtime for dev builds
# so TCC permissions persist across rebuilds
codesign --force --deep --sign "Apple Development: Jason Kneen (E9G8K4TUEW)" \
    --entitlements /tmp/Pucks.entitlements \
    /Applications/Pucks.app

echo "Signed and installed to /Applications/Pucks.app"
echo "Launching..."
open /Applications/Pucks.app
