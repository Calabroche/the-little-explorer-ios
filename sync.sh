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
# `|| true` so a no-match grep (no booted simulator) doesn't abort the
# whole script under `set -e -o pipefail` — without it the script died
# here silently, before it could even print "no booted simulator", and
# the device-install path below never ran.
SIM_ID=$("$XCRUN" simctl list devices booted \
    | grep -E "iPhone|iPad" \
    | head -n 1 \
    | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/' || true)

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
        # Upgrade in place — do NOT uninstall first. Uninstalling wipes
        # the app's keychain entries, which means the user gets booted
        # back to the login screen on every sync. `simctl install`
        # overwrites the existing .app without touching the keychain.
        # Set CLEAN_INSTALL=1 to force a full wipe (e.g. when you really
        # need to reset everything, including login state).
        if [ "${CLEAN_INSTALL:-0}" = "1" ]; then
            echo "▶︎ Clean install — wiping app data…"
            "$XCRUN" simctl uninstall "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
        else
            echo "▶︎ Upgrading in place on simulator (keychain preserved)…"
        fi
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
# Pick the first iPhone in state "connected" OR "available" — devicectl
# reports the latter once the developer disk image has been mounted,
# and that state was previously rejected by the awk filter (silent skip).
# Extract the 36-char UUID from anywhere on the line — "$(NF-1)" doesn't
# work because the model column has spaces ("iPhone 14 Pro (...)").
DEV_LIST=$("$XCRUN" devicectl list devices 2>/dev/null)
DEV_ID=$(echo "$DEV_LIST" \
    | awk '/iPhone/ && (/connected/ || /available/) {
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

# ── Apple Watch install ────────────────────────────────────────────────
# Same logic for the paired Apple Watch. Direct install via devicectl
# is much more reliable than waiting for the iPhone Watch app to push
# the companion bundle (which is invisible-fail-prone on Personal Team
# free dev certs). The iOS app embeds the Watch app too, so this is
# belt-and-suspenders — keeping both installs in sync prevents iOS
# from cleaning up the "orphan companion" if anything desyncs.
#
# Requires Developer Mode ON on the Watch (Settings → Privacy & Security
# → Developer Mode) and the Watch UNLOCKED + on its charger so the
# developer disk image can mount. If either prerequisite is missing,
# devicectl returns an explicit error (10005 / kAMDDeviceLocked) —
# clearer than the silent "couldn't be installed" iOS shows otherwise.
WATCH_ID=$(echo "$DEV_LIST" \
    | awk '/Watch/ && (/connected/ || /available/) {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/) {
                print $i
                exit
            }
        }
    }')

if [ -n "${WATCH_ID:-}" ]; then
    echo "▶︎ Connected Apple Watch: $WATCH_ID"
    WATCH_SCHEME="LittleExplorerWatch"
    WATCH_DERIVED="./DerivedData-Watch"
    rm -rf "$WATCH_DERIVED"

    echo "▶︎ Building Debug for the Apple Watch…"
    "$XCODEBUILD" \
        -project "$PROJECT" \
        -scheme "$WATCH_SCHEME" \
        -destination "generic/platform=watchOS" \
        -configuration Debug \
        -derivedDataPath "$WATCH_DERIVED" \
        -allowProvisioningUpdates \
        -allowProvisioningDeviceRegistration \
        build | tail -n 5

    WATCH_APP="$WATCH_DERIVED/Build/Products/Debug-watchos/${WATCH_SCHEME}.app"
    if [ -d "$WATCH_APP" ]; then
        echo "▶︎ Installing on Apple Watch (may retry — Watch tunnel sometimes takes 2 tries to establish)…"
        # First attempt often fails the tunnel handshake on Personal
        # Team — retry once after a short pause if needed.
        if ! "$XCRUN" devicectl device install app --device "$WATCH_ID" "$WATCH_APP" 2>&1 | tee /tmp/watch-install.log | tail -n 8; then
            echo "↷ First Watch install attempt failed, retrying in 5s…"
            sleep 5
            "$XCRUN" devicectl device install app --device "$WATCH_ID" "$WATCH_APP" | tail -n 8
        fi
    else
        echo "✗ Watch build did not produce an .app at $WATCH_APP"
    fi
else
    echo "↷ No connected Apple Watch — skipping Watch install."
fi

echo "✓ Done.  Latest commit: $(git rev-parse --short HEAD) — $(git log -1 --pretty=%s)"
