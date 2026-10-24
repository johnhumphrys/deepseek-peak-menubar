#!/usr/bin/env bash
# Builds a self-contained .app bundle at dist/DeepSeek Peak.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="DeepSeek Peak"
APP="$ROOT/dist/$APP_NAME.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/DeepSeekPeakBar" "$APP/Contents/MacOS/DeepSeekPeak"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Ad-hoc signature: enough for SMAppService (Launch at Login) to work locally.
if ! codesign --force --sign - "$APP" > /dev/null 2>&1; then
    echo "warning: ad-hoc codesign failed; Launch at Login may not be available"
fi

echo "Built: $APP"
