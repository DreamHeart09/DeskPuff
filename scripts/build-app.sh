#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_VERSION="${DESKPUFF_VERSION:-0.1.0}"
APP_BUILD_NUMBER="${DESKPUFF_BUILD_NUMBER:-1}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "DESKPUFF_VERSION must contain 1 to 3 numeric components (for example 0.1.1)." >&2
  exit 2
fi
if [[ ! "$APP_BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "DESKPUFF_BUILD_NUMBER must contain 1 to 3 numeric components." >&2
  exit 2
fi
SWIFT_CONFIGURATION="${DESKPUFF_CONFIGURATION:-release}"
run_swift_build() {
  if [[ -n "${DESKPUFF_SCRATCH_DIR:-}" && "${DESKPUFF_DISABLE_SWIFT_SANDBOX:-0}" == "1" ]]; then
    swift build -c "$SWIFT_CONFIGURATION" --scratch-path "$DESKPUFF_SCRATCH_DIR" --disable-sandbox "$@"
  elif [[ -n "${DESKPUFF_SCRATCH_DIR:-}" ]]; then
    swift build -c "$SWIFT_CONFIGURATION" --scratch-path "$DESKPUFF_SCRATCH_DIR" "$@"
  elif [[ "${DESKPUFF_DISABLE_SWIFT_SANDBOX:-0}" == "1" ]]; then
    swift build -c "$SWIFT_CONFIGURATION" --disable-sandbox "$@"
  else
    swift build -c "$SWIFT_CONFIGURATION" "$@"
  fi
}
run_swift_build
BIN_DIR="$(run_swift_build --show-bin-path)"
APP="$(pwd)/dist/DeskPuff.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DeskPuff" "$APP/Contents/MacOS/DeskPuff"
cp -R "$BIN_DIR/DeskPuff_DeskPuff.bundle" "$APP/Contents/Resources/"
cp Sources/DeskPuff/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DeskPuff</string>
<key>CFBundleIdentifier</key><string>local.deskpuff.app</string>
<key>CFBundleName</key><string>DeskPuff</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>deskpuff</string></array></dict></array>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -n "${DESKPUFF_GITHUB_URL:-}" ]]; then
  plutil -insert DeskPuffGitHubURL -string "$DESKPUFF_GITHUB_URL" "$APP/Contents/Info.plist"
fi
if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1 && command -v xcodegen >/dev/null 2>&1; then
  WIDGET_PROJECT="$(pwd)/WidgetExtension/DeskPuffWidgets.xcodeproj"
  WIDGET_DERIVED_DIR="${DESKPUFF_WIDGET_DERIVED_DIR:-${TMPDIR:-/tmp}/deskpuff-widget-derived}"
  WIDGET_CONFIGURATION="Debug"
  if [[ "${DESKPUFF_CONFIGURATION:-release}" == "release" ]]; then WIDGET_CONFIGURATION="Release"; fi
  xcodegen generate --spec WidgetExtension/project.yml
  xcodebuild -project "$WIDGET_PROJECT" -scheme DeskPuffWidgetExtension -configuration "$WIDGET_CONFIGURATION" \
    -derivedDataPath "$WIDGET_DERIVED_DIR" -packageCachePath "$WIDGET_DERIVED_DIR/PackageCache" \
    -clonedSourcePackagesDirPath "$WIDGET_DERIVED_DIR/SourcePackages" CODE_SIGNING_ALLOWED=NO build
  WIDGET_APP="$WIDGET_DERIVED_DIR/Build/Products/$WIDGET_CONFIGURATION/DeskPuffWidgetExtension.appex"
  mkdir -p "$APP/Contents/PlugIns"
  cp -R "$WIDGET_APP" "$APP/Contents/PlugIns/DeskPuffWidgetExtension.appex"
  /usr/bin/codesign --force --sign - --entitlements WidgetExtension/Widget.entitlements "$APP/Contents/PlugIns/DeskPuffWidgetExtension.appex"
  /usr/bin/codesign --force --sign - --entitlements WidgetExtension/Host.entitlements "$APP"
else
  /usr/bin/codesign --force --deep --sign - "$APP"
  echo "Widget extension sources are ready; install full Xcode to build and embed the desktop widget."
fi
printf 'Built %s\n' "$APP"
