#!/bin/sh
# build.sh — compile StrataCtl and assemble StrataCtl.app.
set -eu
cd "$(dirname "$0")"

swiftc -O Sources/main.swift -o stratactl \
    -framework Cocoa

APP=StrataCtl.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp stratactl "$APP/Contents/MacOS/StrataCtl"
cp Info.plist "$APP/Contents/Info.plist"

# sign: a local developer identity when present (stable across rebuilds),
# else ad-hoc.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: .*\)".*/\1/p' | head -1)
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --identifier local.stratactl "$APP"
else
    codesign --force --sign - --identifier local.stratactl "$APP"
fi

echo "built: $(pwd)/$APP"
