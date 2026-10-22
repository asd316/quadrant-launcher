#!/bin/zsh
# Builds a release .app bundle and a drag-to-Applications DMG.
# Usage: Scripts/package-dmg.sh [version]
# Output: dist/Quadrant Launcher <version>.dmg
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME="Quadrant Launcher"
BUNDLE_ID="com.quadrantlauncher.app"
VERSION="${1:-${VERSION:-0.1.0}}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME $VERSION.dmg"
BIN=".build/release/QuadrantApp"

if [[ ! -f "Assets/AppIcon.icns" ]]; then
  echo "缺少 Assets/AppIcon.icns" >&2
  exit 1
fi

echo "编译 release…"
swift build -c release --product QuadrantApp --disable-sandbox

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QuadrantApp"
chmod 755 "$APP/Contents/MacOS/QuadrantApp"
cp "Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>QuadrantApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Quadrant Launcher 读取你选择的文件夹，用来展示文件。</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Quadrant Launcher 读取你选择的文件夹，用来展示文件。</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Quadrant Launcher 读取你选择的文件夹，用来展示文件。</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Quadrant Launcher</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "临时签名（ad-hoc）…"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "生成 DMG…"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/quadrant-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$DIST"
hdiutil detach "/Volumes/$APP_NAME" -force >/dev/null 2>&1 || true
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

echo
echo "完成：$DMG"
shasum -a 256 "$DMG"
