#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Universal binary, so the app also runs on Intel Macs it is AirDropped to.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift
APP='build/Samsung TV Remote.app'
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/SamsungTVRemote" "$APP/Contents/MacOS/SamsungTVRemote"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Samsung TV Remote</string>
<key>CFBundleDisplayName</key><string>Samsung TV Remote</string>
<key>CFBundleIdentifier</key><string>local.samsung-tv-remote-mac</string>
<key>CFBundleExecutable</key><string>SamsungTVRemote</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Find and control your Samsung TV on your local network.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
# Zip with ditto so the bundle survives AirDrop and Finder extraction intact.
ZIP='build/Samsung TV Remote.zip'
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
printf '\nBuilt: %s\nShare: %s\n' "$PWD/$APP" "$PWD/$ZIP"
