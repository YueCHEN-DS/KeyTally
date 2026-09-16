#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/KeyTally.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_PNG="$PROJECT_DIR/icon.png"
ICONSET_DIR="$PROJECT_DIR/Resources/AppIcon.iconset"
ICNS_PATH="$PROJECT_DIR/Resources/AppIcon.icns"

cd "$PROJECT_DIR"

# Build a proper macOS .icns from the source PNG if missing or stale.
if [[ ! -f "$ICNS_PATH" || "$ICON_PNG" -nt "$ICNS_PATH" ]]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    # iconutil expects icon_<size>.png and icon_<size>@2x.png names.
    sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
    rm -rf "$ICONSET_DIR"
    echo "Generated $ICNS_PATH"
fi

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$BIN_DIR/KeyTally" "$MACOS_DIR/KeyTally"
install -m 644 "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
install -m 644 "$ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"

# Refresh Launch Services / icon cache for this bundle path.
touch "$APP_DIR"

# KeyTally is intentionally local-only: no Developer ID, Apple team, or
# distribution identity. Each rebuilt ad-hoc binary has a new TCC identity,
# so Input Monitoring must be granted to the final bundle after rebuilding.
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

printf '%s\n' "Built local app: $APP_DIR"
codesign -d --verbose=4 "$APP_DIR" 2>&1 | grep -E '^(Identifier|Signature|TeamIdentifier|CDHash)='
ls -la "$RESOURCES_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"

cat <<'NOTE'

Input Monitoring note
---------------------
KeyTally is ad-hoc signed. Rebuilding changes its designated requirement, so
macOS requires Input Monitoring to be granted to the new final bundle.

If counting still stops:
  1. Quit KeyTally
  2. System Settings → Privacy & Security → Input Monitoring
  3. Toggle KeyTally off, then on (or remove and re-add this .app)
  4. Reopen KeyTally and press "Recheck Keyboard Access"

Clean slate for this bundle id only:
  tccutil reset ListenEvent com.local.keytally
NOTE
