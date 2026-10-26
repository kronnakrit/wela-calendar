#!/bin/bash
# Screenshots on the foldable iPhone simulator, which needs the newest Xcode. Builds the app with
# that Xcode, creates the simulator if needed, and captures light and dark.
#   scripts/ios-fold-screenshots.sh <output dir>
set -euo pipefail
OUT="$1"
mkdir -p "$OUT"

XCODE=$(ls -d /Applications/Xcode*.app | sort -V | tail -1)
echo "Using $XCODE"
sudo xcode-select -s "$XCODE"
xcodebuild -version

# Any device type with "Fold" in its name.
TYPE=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
types = [t for t in json.load(sys.stdin)["devicetypes"] if "fold" in t["name"].lower()]
print(types[-1]["identifier"] if types else "")')
if [ -z "$TYPE" ]; then
  echo "::warning::No foldable iPhone simulator in $XCODE"
  xcrun simctl list devicetypes | grep -i iphone || true
  exit 0
fi
echo "Device type: $TYPE"

latest_runtime() {
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(rs[-1]["identifier"] if rs else "")'
}
RUNTIME=$(latest_runtime)
if [ -z "$RUNTIME" ]; then
  xcodebuild -downloadPlatform iOS
  RUNTIME=$(latest_runtime)
fi
echo "Runtime: $RUNTIME"
UDID=$(xcrun simctl create "Wela Fold" "$TYPE" "$RUNTIME")

xcodebuild build -project Wela.xcodeproj -scheme WelaiOS -configuration Debug \
  -destination "id=$UDID" -derivedDataPath DerivedDataFold CODE_SIGNING_ALLOWED=NO -quiet
APP=DerivedDataFold/Build/Products/Debug-iphonesimulator/Wela.app
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"
# Log any fold / posture controls this simctl offers, for the inner-screen capture.
xcrun simctl help 2>&1 | grep -iE "fold|posture|hinge" || echo "simctl: no fold command listed"
for mode in light dark; do
  xcrun simctl ui "$UDID" appearance "$mode"
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -UseMockData
  sleep 8
  xcrun simctl io "$UDID" screenshot "$OUT/sim-fold-$mode.png"
done
xcrun simctl shutdown "$UDID" || true
ls -la "$OUT"
