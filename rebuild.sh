#!/usr/bin/env bash
#
# Everyday dev loop: build the .app and launch (or relaunch) it.
# Composes ./build.sh + a kill+open dance for the running instance.

set -euo pipefail

cd "$(dirname "$0")"

APP="VoicePTT.app"
BIN_NAME="VoicePTT"

./build.sh

if pgrep -f "$APP/Contents/MacOS/$BIN_NAME" >/dev/null 2>&1; then
    echo "==> restarting running app"
    killall -9 "$BIN_NAME" 2>/dev/null || true
    sleep 0.4
fi
open "$APP"
