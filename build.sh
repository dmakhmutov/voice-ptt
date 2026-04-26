#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="VoicePTT.app"
BIN_NAME="VoicePTT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"

echo "==> packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo "==> done: $APP"
echo "    open $APP   # to launch"
