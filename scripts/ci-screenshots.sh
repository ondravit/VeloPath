#!/bin/bash
# Boots an iPhone simulator, installs the app and captures screenshots of key states.
set -x
APP=build/Build/Products/Debug-iphonesimulator/VeloPath.app
BUNDLE=com.ondrejvit.VeloPath
OUT=ci-out/screenshots
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
phones = [x for k, v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone")]
pref = [x for x in phones if x["name"].endswith("Pro")] or phones
print(pref[-1]["udid"])')
xcrun simctl list devices | grep "$UDID" | tee "$OUT/device.txt"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 || true
xcrun simctl location "$UDID" set 50.2092,15.8327 || true
xcrun simctl install "$UDID" "$APP"

shoot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
  xcrun simctl launch "$UDID" "$BUNDLE" "$@"
  sleep 14
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
}

shoot 01-empty
shoot 02-route-compact -uiDemo
shoot 03-route-medium -uiDemo -uiDetent medium
shoot 04-route-large -uiDemo -uiDetent large
shoot 05-settings -uiDemo -uiSettings
shoot 07-long-route -uiDemo -uiDemoLong
xcrun simctl ui "$UDID" appearance dark
shoot 06-dark-medium -uiDemo -uiDetent medium

xcrun simctl spawn "$UDID" log show --last 5m --style compact --predicate 'process == "VeloPath"' > ci-out/app-log.txt 2>&1 || true
ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i velopath && cp ~/Library/Logs/DiagnosticReports/*VeloPath* ci-out/ 2>/dev/null
exit 0
