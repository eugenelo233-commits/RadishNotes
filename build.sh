#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
python3 scripts/fetch-fonts.py --check
APP="${RADISH_BUILD_APP:-$PWD/萝卜便签.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build
SDK="$(xcrun --show-sdk-path)"
xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target arm64-apple-macosx14.0 -module-cache-path .build/ModuleCache Sources/*.swift -o "$APP/Contents/MacOS/RadishNotes" -framework AppKit -framework SwiftUI -framework Carbon
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RadishNotes</string>
<key>CFBundleIdentifier</key><string>local.radishnotes.mac</string>
<key>CFBundleName</key><string>萝卜便签</string>
<key>CFBundleDisplayName</key><string>萝卜便签</string>
<key>CFBundleIconFile</key><string>Radish</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>仅在专注时读取 Edge 当前网页域名，判断是否在学习名单；不读取页面正文、不录屏、不上传。</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
cp Tools/Radish.icns "$APP/Contents/Resources/Radish.icns"
cp Resources/paper-rustle.wav "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Fonts"
rsync -a --delete Resources/Fonts/ "$APP/Contents/Resources/Fonts/"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
