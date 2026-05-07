#!/usr/bin/env bash
# sync.sh — pull the latest, regenerate the Xcode project, build,
# uninstall + reinstall + relaunch the app on the booted simulator.
#
# Usage:  ./sync.sh
#
# Why this exists: Cmd+R in Xcode caches builds aggressively, and after
# a `git pull` the simulator can keep showing an old version because
# DerivedData has a stale .app sitting around. This script wipes the
# build folder and forces a clean install on whatever simulator you
# have booted, so the on-screen app always matches the current source.

set -euo pipefail
cd "$(dirname "$0")"

# Find Xcode (CLT-active xcode-select would otherwise refuse xcodebuild).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUNDLE_ID="com.calabrese.little-explorer-ios"
SCHEME="LittleExplorer"
PROJECT="LittleExplorer.xcodeproj"
DERIVED="./DerivedData"

echo "▶︎ Pulling latest from origin/main…"
git pull --ff-only origin main

echo "▶︎ Regenerating Xcode project…"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "✗ xcodegen not installed.  brew install xcodegen"
    exit 1
fi
xcodegen generate

echo "▶︎ Locating booted simulator…"
SIM_ID=$("$DEVELOPER_DIR/usr/bin/xcrun" simctl list devices booted \
    | grep -E "iPhone|iPad" \
    | head -n 1 \
    | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
if [ -z "${SIM_ID:-}" ]; then
    echo "✗ No booted iOS simulator. Open Simulator first (Xcode → Open Developer Tool → Simulator)."
    exit 1
fi
echo "  ↳ $SIM_ID"

echo "▶︎ Cleaning build folder…"
rm -rf "$DERIVED"

echo "▶︎ Building Debug for the booted simulator…"
"$DEVELOPER_DIR/usr/bin/xcodebuild" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build | tail -n 5

APP="$DERIVED/Build/Products/Debug-iphonesimulator/${SCHEME}.app"
if [ ! -d "$APP" ]; then
    echo "✗ Build did not produce an .app at $APP"
    exit 1
fi

echo "▶︎ Reinstalling on simulator…"
"$DEVELOPER_DIR/usr/bin/xcrun" simctl uninstall "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
"$DEVELOPER_DIR/usr/bin/xcrun" simctl install   "$SIM_ID" "$APP"

echo "▶︎ Launching…"
"$DEVELOPER_DIR/usr/bin/xcrun" simctl launch    "$SIM_ID" "$BUNDLE_ID" >/dev/null

# Bring Simulator to the foreground so you can see the result.
open -a Simulator

echo "✓ Done.  Latest commit: $(git rev-parse --short HEAD) — $(git log -1 --pretty=%s)"
