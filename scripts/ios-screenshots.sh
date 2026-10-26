#!/bin/bash
# Launches the Debug iOS build with mock data on an iPhone and an iPad simulator, in light and
# dark, and saves a screenshot of each. Used by CI; also works locally after `make ios-build`.
#   scripts/ios-screenshots.sh <path to Wela.app> <output dir>
set -euo pipefail
APP="$1"
OUT="$2"
mkdir -p "$OUT"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")

# Newest available simulator whose name starts with the given prefix.
pick() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
prefix = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
found = [d["udid"] for runtime, ds in sorted(devices.items()) if "iOS" in runtime
         for d in ds if d["name"].startswith(prefix)]
print(found[-1] if found else "")' "$1"
}

shoot() {
  local name="$1" udid="$2"
  if [ -z "$udid" ]; then echo "No simulator for $name"; return; fi
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 || true
  xcrun simctl install "$udid" "$APP"
  for mode in light dark; do
    xcrun simctl ui "$udid" appearance "$mode"
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" -UseMockData
    sleep 8
    xcrun simctl io "$udid" screenshot "$OUT/sim-$name-$mode.png"
  done
  xcrun simctl terminate "$udid" "$BUNDLE" || true
  xcrun simctl shutdown "$udid" || true
}

shoot iphone "$(pick 'iPhone 16 Pro')"
IPAD=$(pick 'iPad Pro 13')
[ -n "$IPAD" ] || IPAD=$(pick 'iPad')
shoot ipad "$IPAD"
ls -la "$OUT"
