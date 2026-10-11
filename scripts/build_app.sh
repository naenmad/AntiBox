#!/bin/bash
set -e

# Script to build and package AntiBox into a native macOS .app bundle
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "==> Building AntiBox with swift build..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/AntiBox"
APP_DIR="$PROJECT_DIR/AntiBox.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating AntiBox.app bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "==> Copying executable and Info.plist..."
cp "$BIN_PATH" "$MACOS_DIR/AntiBox"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "==> AntiBox.app built successfully at: $APP_DIR"
echo "==> To launch AntiBox, run: open AntiBox.app"
