#!/bin/bash
# Builds an unsigned Release IPA (install with Sideloadly / AltStore, which re-sign it
# with your Apple ID) and publishes it as the "build-latest" GitHub pre-release.
set -eo pipefail
xcodebuild -project VeloPath.xcodeproj -scheme VeloPath -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build-device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | tee ci-out/build-device.log | grep -E "error:|BUILD" || true
grep -q "BUILD SUCCEEDED" ci-out/build-device.log
rm -rf Payload && mkdir Payload
cp -R build-device/Build/Products/Release-iphoneos/VeloPath.app Payload/
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Payload/VeloPath.app/Info.plist)
IPA="VeloPath-${VERSION}-${GITHUB_SHA::7}.ipa"
zip -qry "$IPA" Payload
ls -la "$IPA" | tee ci-out/ipa.txt
gh release delete build-latest --yes --cleanup-tag 2>/dev/null || true
gh release create build-latest "$IPA" --prerelease --target "$GITHUB_SHA" \
  --title "VeloPath ${VERSION} – poslední build (${GITHUB_SHA::7})" \
  --notes "Nepodepsaný build pro instalaci přes Sideloadly. Commit ${GITHUB_SHA}, větev ${GITHUB_REF_NAME}."
echo "https://github.com/${GITHUB_REPOSITORY}/releases/tag/build-latest" >> ci-out/ipa.txt
