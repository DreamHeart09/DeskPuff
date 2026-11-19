#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: make dmg 0.1.1" >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "Version must contain 1 to 3 numeric components (for example 0.1.1)." >&2
  exit 2
fi
if [[ ! -t 0 ]]; then
  echo "Run this release command from an interactive terminal to confirm asset rights." >&2
  exit 2
fi
read -r -p "Have you confirmed release rights for all bundled assets? [y/N] " ASSETS_CONFIRMED
if [[ ! "$ASSETS_CONFIRMED" =~ ^[Yy]$ ]]; then
  echo "DMG creation cancelled. Confirm asset rights before release." >&2
  exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  echo "A complete Xcode installation is required to build the release app and WidgetKit extension." >&2
  exit 2
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to build the WidgetKit extension (install it with: brew install xcodegen)." >&2
  exit 2
fi
for tool in swift codesign hdiutil shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required macOS tool not found: $tool" >&2
    exit 2
  fi
done

DESKPUFF_CONFIGURATION=release \
DESKPUFF_VERSION="$VERSION" \
DESKPUFF_BUILD_NUMBER="$VERSION" \
  ./scripts/build-app.sh

APP="$ROOT/dist/DeskPuff.app"
test -x "$APP/Contents/MacOS/DeskPuff"
test -d "$APP/Contents/Resources/DeskPuff_DeskPuff.bundle"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
SIGNATURE_INFO="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
if ! grep -q 'Signature=adhoc' <<<"$SIGNATURE_INFO"; then
  echo "Expected the source build's ad-hoc signature; refusing to package an unexpected signing state." >&2
  exit 2
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/deskpuff-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
cp "$ROOT/ASSET_LICENSE.md" "$STAGE/ASSET_LICENSE.md"
cat > "$STAGE/INSTALL.txt" <<'INSTALL'
DeskPuff — community build for Apple Silicon

This app is ad-hoc signed and is not notarized by Apple. macOS may block the
first launch.

Before opening it, verify the published SHA-256 checksum and download it from
the project's official release page. If you trust the source and macOS blocks
the app, try opening it once, then go to System Settings > Privacy & Security
and choose Open Anyway for DeskPuff. Do not disable Gatekeeper globally.

Drag DeskPuff.app to Applications. Source code and build instructions are
available from the project repository. See LICENSE.txt and ASSET_LICENSE.md.
INSTALL

mkdir -p "$ROOT/dist"
DMG="$ROOT/dist/DeskPuff-$VERSION-arm64.dmg"
hdiutil create \
  -volname "DeskPuff $VERSION" \
  -srcfolder "$STAGE" \
  -format UDZO \
  -ov \
  "$DMG"
hdiutil verify "$DMG"
(cd "$ROOT/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo "Created $DMG"
echo "Created $DMG.sha256"
echo "Signing: ad-hoc; notarization: none."
