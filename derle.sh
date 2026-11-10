#!/bin/zsh
# Kilit.app'i derler. Kullanım: ./derle.sh
set -e
cd "$(dirname "$0")"
APP=Kilit.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -swift-version 5 main.swift -o $APP/Contents/MacOS/Kilit -framework Cocoa -framework SwiftUI
cat > $APP/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.biontra.kilit</string>
  <key>CFBundleName</key><string>Kilit</string>
  <key>CFBundleDisplayName</key><string>Kilit</string>
  <key>CFBundleExecutable</key><string>Kilit</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --sign - --identifier io.github.biontra.kilit -r='designated => identifier "io.github.biontra.kilit"' $APP
echo "Hazır: $(pwd)/$APP"
