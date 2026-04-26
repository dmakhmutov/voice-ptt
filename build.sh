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

# Launch (or relaunch) the app after a successful build. Skipped when
# called from release.sh — we want the old version to stay up so the
# in-app 'Download & install' has something to update from. Override
# manually with NO_RESTART=1.
if [ -z "${NO_RESTART:-}" ]; then
    if pgrep -f "$APP/Contents/MacOS/$BIN_NAME" >/dev/null 2>&1; then
        echo "==> restarting running app"
        killall -9 "$BIN_NAME" 2>/dev/null || true
        sleep 0.4
    fi
    open "$APP"
fi
