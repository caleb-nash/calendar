#!/bin/bash
# Rebuilds and reinstalls Claude Mini, then reports exactly where it fails:
# a build error, a crash on launch, or (if it's running) its recent log.
cd "$(dirname "$0")"
mkdir -p build
LOG=build/doctor-build.log

echo "== 1. Building =="
swift build -c release > "$LOG" 2>&1
if ! grep -q "Build complete" "$LOG"; then
    echo "BUILD FAILED. Screenshot everything below:"
    echo
    grep -E "error:" "$LOG" | head -20
    [ -z "$(grep -E 'error:' "$LOG")" ] && tail -30 "$LOG"
    exit 1
fi
echo "Build OK"

echo "== 2. Installing =="
./build.sh install > /dev/null 2>&1 || { echo "Install failed:"; ./build.sh install; exit 1; }
sleep 3

echo "== 3. Checking it's running =="
if pgrep -x ClaudeMini > /dev/null; then
    echo "RUNNING. Recent log (screenshot this if a shortcut still doesn't work):"
    log show --last 2m --info --predicate 'subsystem == "com.calebnash.ClaudeMini"' | grep -E "Registration|Hotkey|failed|error" | tail -15
else
    echo "NOT RUNNING: it crashed on launch. Screenshot everything below:"
    "/Applications/Claude Mini.app/Contents/MacOS/ClaudeMini" &
    PID=$!
    sleep 5
    kill $PID 2>/dev/null
fi
