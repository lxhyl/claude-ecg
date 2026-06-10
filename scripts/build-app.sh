#!/usr/bin/env bash
# Builds ECGBar.app into ./build, ready to drop into /Applications.
#
# Signing: set CODESIGN_IDENTITY to a "Developer ID Application: ..." identity
# for distribution (signs with hardened runtime, ready for notarization).
# Defaults to ad-hoc signing for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/ECGBar/AppConfig.swift)
APP=build/ECGBar.app
IDENTITY="${CODESIGN_IDENTITY:--}"

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

if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
    echo "Built $APP (v${VERSION}, ad-hoc signed)."
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    echo "Built $APP (v${VERSION}, signed as: $IDENTITY)."
fi
