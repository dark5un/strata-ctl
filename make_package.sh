#!/bin/sh
# make_package.sh — build a universal StrataCtl.app and bundle it into a
# package that needs NO dev tools on the target Mac.
#
#   ./make_package.sh  ->  dist/strata-ctl-<version>-macos.tar.gz
#                          dist/strata-ctl-<version>-macos.dmg
set -eu
cd "$(dirname "$0")"

VERSION=$(sed -n 's|.*CFBundleShortVersionString</key><string>\(.*\)</string>.*|\1|p' Info.plist)
[ -n "$VERSION" ] || VERSION="1.0"
STAGE="dist/strata-ctl"
OUT_DIR="dist"

rm -rf "$STAGE" "$OUT_DIR/StrataCtl.app"
mkdir -p "$OUT_DIR"

# --- universal build (arm64 + x86_64) --------------------------------------
APP="StrataCtl.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target arm64-apple-macos13  Sources/main.swift -o /tmp/stratactl-arm64  -framework Cocoa
swiftc -O -target x86_64-apple-macos13 Sources/main.swift -o /tmp/stratactl-x86_64 -framework Cocoa 2>/dev/null || \
    echo "note: x86_64 slice failed (this Mac's SDK); packaging arm64 only"
if [ -f /tmp/stratactl-x86_64 ]; then
    lipo -create /tmp/stratactl-arm64 /tmp/stratactl-x86_64 -output "$APP/Contents/MacOS/StrataCtl"
else
    cp /tmp/stratactl-arm64 "$APP/Contents/MacOS/StrataCtl"
fi
lipo -archs "$APP/Contents/MacOS/StrataCtl"

cp Info.plist "$APP/Contents/Info.plist"

# sign: CODESIGN_IDENTITY wins (CI sets the Developer ID name); else a local
# "Apple Development" identity when present; else ad-hoc. Developer ID builds
# get the hardened runtime, which notarization requires.
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" --identifier local.stratactl "$APP"
else
    IDENTITY=$(security find-identity -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: .*\)".*/\1/p' | head -1)
    if [ -n "$IDENTITY" ]; then
        codesign --force --deep --sign "$IDENTITY" --identifier local.stratactl "$APP"
    else
        codesign --force --deep --sign - --identifier local.stratactl "$APP"
    fi
fi

# --- the package payload ----------------------------------------------------
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp README.md "$STAGE/README.md"
cat > "$STAGE/install.sh" <<'EOF'
#!/bin/sh
# install.sh — copy StrataCtl.app into ~/Applications and launch it.
set -eu
cd "$(dirname "$0")"
APP="$HOME/Applications/StrataCtl.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R StrataCtl.app "$APP"
open "$APP"
echo "installed: $APP"
EOF
chmod +x "$STAGE/install.sh"

TARBALL="$OUT_DIR/strata-ctl-$VERSION-macos.tar.gz"
tar -czf "$TARBALL" -C "$OUT_DIR" "strata-ctl"

DMG="$OUT_DIR/strata-ctl-$VERSION-macos.dmg"
DMG_DIR="$OUT_DIR/dmg-root"
rm -rf "$DMG_DIR"; mkdir -p "$DMG_DIR"
cp -R "$APP" "$DMG_DIR/"
cp README.md "$DMG_DIR/README.md"
cp "$STAGE/install.sh" "$DMG_DIR/install.command"
chmod +x "$DMG_DIR/install.command"
hdiutil create -volname "strata-ctl" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMG_DIR"

echo
echo "package built:"
echo "  $(pwd)/$TARBALL"
echo "  $(pwd)/$DMG"
