#!/bin/bash
# Builds WinkBox Play into WinkPlay.ipa. This runs on GitHub's Mac machines, which have Xcode (see
# .github/workflows/build.yml), and the finished WinkPlay.ipa is published as the "latest" release. On a Mac with
# only the Command Line Tools it can build too, if an iPhone SDK has been put in sdk/ (the WinkBox Remote project
# has Tools/extract-sdk.py for pulling one out of an Xcode .xip). Install the .ipa with Sideloadly.
set -euo pipefail
cd "$(dirname "$0")"

if SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null); then
  SWIFTC=(xcrun --sdk iphoneos swiftc)
  SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
else
  DEVROOT=sdk
  SDK=$DEVROOT/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
  XTC=$DEVROOT/Toolchains/XcodeDefault.xctoolchain/usr/lib
  CLT=/Library/Developer/CommandLineTools/usr/lib
  [ -d "$SDK" ] || { echo "No Xcode and no iPhone SDK in $SDK (see the note at the top of this file)."; exit 1; }
  # Swift's resource folder for iPhone builds: the Mac's shims plus Xcode's iPhone runtime pieces and clang folder.
  RES=.build/swift-resource
  if [ ! -d "$RES/iphoneos" ]; then
    mkdir -p "$RES"
    ln -sfn "$PWD/$XTC/swift/iphoneos" "$RES/iphoneos"
    ln -sfn "$CLT/swift/shims" "$RES/shims"
    ln -sfn "$PWD/$(ls -d $XTC/clang/* | head -1)" "$RES/clang"
  fi
  SWIFTC=(/Library/Developer/CommandLineTools/usr/bin/swiftc -resource-dir "$RES")
  SDK_VERSION=$(/usr/libexec/PlistBuddy -c "Print :Version" "$SDK/SDKSettings.plist")
fi

OUT=.build/ios
APP=$OUT/Payload/WinkPlay.app
rm -rf "$OUT"
mkdir -p "$APP"

echo "Compiling against the iOS $SDK_VERSION SDK…"
"${SWIFTC[@]}" \
  -target arm64-apple-ios16.0 -sdk "$SDK" -swift-version 5 \
  -module-name WinkPlay -parse-as-library -O -wmo \
  -module-cache-path .build/ModuleCache \
  App/Core/*.swift App/UI/*.swift App/Main/*.swift \
  -o "$APP/WinkPlay"

cp App/Icon/AppIcon??x??@?x.png "$APP/"
cp App/Info.plist "$APP/Info.plist"
plutil -replace DTPlatformVersion -string "$SDK_VERSION" "$APP/Info.plist"
plutil -replace DTSDKName -string "iphoneos$SDK_VERSION" "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"

rm -f WinkPlay.ipa
(cd "$OUT" && zip -qry ../../WinkPlay.ipa Payload)
echo "Built $(pwd)/WinkPlay.ipa ($(du -h WinkPlay.ipa | cut -f1))"
