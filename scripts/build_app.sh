#!/bin/bash
set -e

# Script to build and package ZedGravity into a native macOS .app bundle
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "==> Building ZedGravity with swift build..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/ZedGravity"
APP_DIR="$PROJECT_DIR/ZedGravity.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating ZedGravity.app bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "==> Copying executable, Info.plist, and AppIcon..."
cp "$BIN_PATH" "$MACOS_DIR/ZedGravity"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -d "$PROJECT_DIR/Assets" ]; then
    cp -R "$PROJECT_DIR/Assets/"* "$RESOURCES_DIR/"
fi

echo "==> ZedGravity.app built successfully at: $APP_DIR"

if [ "$1" == "--install" ] || [ "$1" == "-i" ]; then
    echo "==> Installing to /Applications..."
    rm -rf "/Applications/ZedGravity.app"
    cp -R "$APP_DIR" "/Applications/ZedGravity.app"
    echo "==> ZedGravity.app successfully installed to /Applications/ZedGravity.app!"
fi
