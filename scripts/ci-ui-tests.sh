#!/bin/bash
# Runs the XCUITest suite on the iPhone simulator and exports screenshot attachments.
set -o pipefail
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
phones = [x for k, v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone")]
pref = [x for x in phones if x["name"].endswith("Pro")] or phones
print(pref[-1]["udid"])')
xcrun simctl ui "$UDID" appearance light || true
rm -rf ci-out/UITests.xcresult
xcodebuild test -project VeloPath.xcodeproj -scheme VeloPath -destination "id=$UDID" \
  -derivedDataPath build -resultBundlePath ci-out/UITests.xcresult CODE_SIGNING_ALLOWED=NO 2>&1 \
  | tee ci-out/ui-tests.log | grep -E "Test Case|error:|failed|passed|TEST (SUCCEEDED|FAILED)"
STATUS=${PIPESTATUS[0]}
mkdir -p ci-out/ui-test-shots
xcrun xcresulttool export attachments --path ci-out/UITests.xcresult --output-path ci-out/ui-test-shots 2>&1 | tail -3 || true
rm -rf ci-out/UITests.xcresult
exit $STATUS
