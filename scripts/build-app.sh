#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP='build/Samsung Menu Remote.app'
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/SamsungMenuRemote" "$APP/Contents/MacOS/SamsungMenuRemote"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Samsung Menu Remote</string>
<key>CFBundleDisplayName</key><string>Samsung Menu Remote</string>
<key>CFBundleIdentifier</key><string>local.samsung-menu-remote</string>
<key>CFBundleExecutable</key><string>SamsungMenuRemote</string>
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
printf '\nBuilt: %s\n' "$PWD/$APP"
