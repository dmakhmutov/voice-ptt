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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_IDENTITY="${SIGN_IDENTITY:-VoicePTT Local}"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    echo "==> codesign with stable identity '$SIGN_IDENTITY'"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
else
    echo "==> ad-hoc codesign (no '$SIGN_IDENTITY' cert in keychain)"
    codesign --force --deep --sign - "$APP"
fi

echo "==> done: $APP"
echo "    open $APP   # to launch"
