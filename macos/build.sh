#!/bin/zsh
# Builds WolfClip.app. `./build.sh install` also copies it to /Applications and restarts it.
set -euo pipefail
# Use Command Line Tools even if Xcode is selected (its license/SDK may not match).
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
cd "${0:A:h}"

APP=build/WolfClip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONSET=build/AppIcon.iconset
  mkdir -p "$ICONSET"
  swift tools/make_icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

# arm64 by default; UNIVERSAL=1 also builds x86_64 and merges both into one binary.
ARCHS=(arm64)
[[ -n "${UNIVERSAL:-}" ]] && ARCHS=(arm64 x86_64)
for arch in $ARCHS; do
  swiftc -O -swift-version 5 ${WOLFCLIP_DEBUG:+-DWOLFCLIP_DEBUG} -target $arch-apple-macos14.0 -parse-as-library \
    -module-cache-path build/cache-$arch Sources/*.swift -o build/WolfClip-$arch
done
lipo -create build/WolfClip-${^ARCHS} -output "$APP/Contents/MacOS/WolfClip"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${WOLFCLIP_DEBUG:-}" ]]; then
  # Separate identity for the test build, so it never collides with the installed app.
  plutil -replace CFBundleIdentifier -string one.wolfteam.wolfclip.debug "$APP/Contents/Info.plist"
  plutil -replace CFBundleURLTypes.0.CFBundleURLSchemes.0 -string wolfclip-debug "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature with a designated requirement by bundle id (not by binary hash),
# so the Accessibility permission survives rebuilds.
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")
codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x WolfClip || true
  sleep 0.5
  rm -rf /Applications/WolfClip.app
  cp -R "$APP" /Applications/
  open /Applications/WolfClip.app
  echo "Installed to /Applications/WolfClip.app"
fi
