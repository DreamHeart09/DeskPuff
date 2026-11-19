#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OPTIONS=()
if [[ -n "${DESKPUFF_SCRATCH_DIR:-}" ]]; then OPTIONS+=(--scratch-path "$DESKPUFF_SCRATCH_DIR"); fi
if [[ "${DESKPUFF_DISABLE_SWIFT_SANDBOX:-0}" == "1" ]]; then OPTIONS+=(--disable-sandbox); fi
CONFIG="${DESKPUFF_CONFIGURATION:-debug}"
swift build -c "$CONFIG" --product FlameLab "${OPTIONS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" --product FlameLab "${OPTIONS[@]}" --show-bin-path)"
APP="$(pwd)/dist/FlameLab.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FlameLab" "$APP/Contents/MacOS/FlameLab"
cp -R "$BIN_DIR/DeskPuff_FlameLab.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FlameLab</string>
<key>CFBundleIdentifier</key><string>local.deskpuff.flamelab</string>
<key>CFBundleName</key><string>Flame Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf 'Built %s\n' "$APP"
