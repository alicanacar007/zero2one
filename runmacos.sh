#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

swift build -c debug

APP_NAME="HowToApp"
BUILD_DIR=".build/debug"
BIN_PATH="$BUILD_DIR/$APP_NAME"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

if [ ! -x "$BIN_PATH" ]; then
  echo "Built binary not found at $BIN_PATH"
  exit 1
fi

mkdir -p "$MACOS_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.howto.app</string>
    <key>CFBundleName</key>
    <string>zero2one</string>
    <key>CFBundleExecutable</key>
    <string>HowToApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
EOF

open "$APP_BUNDLE"
