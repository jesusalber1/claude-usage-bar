#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsageBar"
BUILT_APP="$SCRIPT_DIR/app/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

bash "$SCRIPT_DIR/app/build.sh"

echo "Stopping running instance (if any)..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

echo "Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "Launching..."
open "$INSTALL_PATH"

echo "Done."
