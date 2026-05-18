#!/usr/bin/env bash
# sync.sh — pull the latest, regenerate the Xcode project, build,
# and install the app onto:
#   - the booted iOS Simulator (if one is running), AND
#   - every connected physical iPhone with developer mode enabled
#
# Usage:  ./sync.sh
#
# Why this exists: Cmd+R in Xcode caches builds aggressively, and after
# a `git pull` the simulator (and the iPhone) can keep showing an old
# version because DerivedData has a stale .app sitting around. This
# script wipes the build folder and forces a clean install on whichever
# targets are available — simulator AND device get refreshed together.

set -euo pipefail
cd "$(dirname "$0")"

# Find Xcode (CLT-active xcode-select would otherwise refuse xcodebuild).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUNDLE_ID="com.calabrese.little-explorer-ios"
SCHEME="LittleExplorer"
PROJECT="LittleExplorer.xcodeproj"
DERIVED_SIM="./DerivedData"
DERIVED_DEV="./DerivedData-Device"

XCRUN="/usr/bin/xcrun"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"

echo "▶︎ Pulling latest from origin/main…"
git pull --ff-only origin main

echo "▶︎ Regenerating Xcode project…"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "✗ xcodegen not installed.  brew install xcodegen"
    exit 1
fi
xcodegen generate

# ── Simulator install ──────────────────────────────────────────────────
SIM_ID=$("$XCRUN" simctl list devices booted \
    | grep -E "iPhone|iPad" \
    | head -n 1 \
    | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')

if [ -n "${SIM_ID:-}" ]; then
    echo "▶︎ Booted simulator: $SIM_ID"
    echo "▶︎ Cleaning simulator build folder…"
    rm -rf "$DERIVED_SIM"

    echo "▶︎ Building Debug for the simulator…"
    "$XCODEBUILD" \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$SIM_ID" \
        -configuration Debug \
        -derivedDataPath "$DERIVED_SIM" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        build | tail -n 5

    SIM_APP="$DERIVED_SIM/Build/Products/Debug-iphonesimulator/${SCHEME}.app"
    if [ -d "$SIM_APP" ]; then
        echo "▶︎ Reinstalling on simulator…"
        "$XCRUN" simctl uninstall "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
        "$XCRUN" simctl install "$SIM_ID" "$SIM_APP"
        echo "▶︎ Launching on simulator…"
        "$XCRUN" simctl launch "$SIM_ID" "$BUNDLE_ID" >/dev/null
        open -a Simulator
    else
        echo "✗ Simulator build did not produce an .app at $SIM_APP"
    fi
else
    echo "↷ No booted iOS simulator — skipping simulator install."
fi

# ── Physical device install ────────────────────────────────────────────
# Pick the first connected iPhone (state "connected"). Extract the
# 36-char UUID from anywhere on the line — "$(NF-1)" doesn't work
# because the model column has spaces ("iPhone 14 Pro (...)").
DEV_ID=$("$XCRUN" devicectl list devices 2>/dev/null \
    | awk '/iPhone/ && /connected/ {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/) {
                print $i
                exit
            }
        }
    }')

if [ -n "${DEV_ID:-}" ]; then
    echo "▶︎ Connected iPhone: $DEV_ID"
    echo "▶︎ Cleaning device build folder…"
    rm -rf "$DERIVED_DEV"

    echo "▶︎ Building Debug for the iPhone…"
    "$XCODEBUILD" \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS,id=$DEV_ID" \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DEV" \
        -allowProvisioningUpdates \
        -allowProvisioningDeviceRegistration \
        build | tail -n 5

    DEV_APP="$DERIVED_DEV/Build/Products/Debug-iphoneos/${SCHEME}.app"
    if [ -d "$DEV_APP" ]; then
        echo "▶︎ Installing on iPhone…"
        "$XCRUN" devicectl device install app --device "$DEV_ID" "$DEV_APP"
        echo "  (launch on iPhone manually — iOS blocks remote launches that haven't been trusted yet)"
    else
        echo "✗ Device build did not produce an .app at $DEV_APP"
    fi
else
    echo "↷ No connected iPhone — skipping device install."
fi

echo "✓ Done.  Latest commit: $(git rev-parse --short HEAD) — $(git log -1 --pretty=%s)"
