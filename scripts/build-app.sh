#!/usr/bin/env bash
# Builds ECGBar.app (ad-hoc signed) into ./build, ready to drop into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/ECGBar/AppConfig.swift)
APP=build/ECGBar.app

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ECGBar "$APP/Contents/MacOS/ECGBar"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ECGBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.lxhyl.ECGBar</string>
    <key>CFBundleName</key>
    <string>ECGBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

echo "Built $APP (v${VERSION})."
echo "Move it to /Applications and optionally add it to Login Items."
