#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsageBar"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Generate app icon
"$SCRIPT_DIR/make_icon.sh"

# Copy icon if it exists
if [ -f "$SCRIPT_DIR/$APP_NAME.icns" ]; then
    cp "$SCRIPT_DIR/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Compile Swift
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macos13.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework SwiftUI \
    -framework AppKit \
    -parse-as-library \
    "$SCRIPT_DIR/$APP_NAME.swift"

# Ad-hoc codesign (required for UserNotifications, LaunchServices registration, etc.)
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Build complete: $APP_BUNDLE"
echo ""
echo "Run with: open $APP_BUNDLE"
