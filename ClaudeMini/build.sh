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
    # Wait for the old copy to fully quit; launching too early fails with error -600.
    for _ in {1..20}; do pgrep -x ClaudeMini >/dev/null || break; sleep 0.25; done
    rm -rf "/Applications/Claude Mini.app"
    cp -R "$APP" /Applications/
    # macOS sometimes refuses to launch right after the old copy quits (error -600); retry.
    for attempt in 1 2 3 4 5; do
        if open "/Applications/Claude Mini.app" 2>/dev/null; then
            echo "Installed to /Applications and launched"
            exit 0
        fi
        sleep 1
    done
    echo "Installed, but macOS wouldn't launch it. Run: open \"/Applications/Claude Mini.app\""
fi
