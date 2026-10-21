#!/bin/bash
# Builds Claude Mini.app into ./build. Run `./build.sh install` to also copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudeMini"

APP="build/Claude Mini.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeMini"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x ClaudeMini 2>/dev/null || true
    rm -rf "/Applications/Claude Mini.app"
    cp -R "$APP" /Applications/
    open "/Applications/Claude Mini.app"
    echo "Installed to /Applications and launched"
fi
