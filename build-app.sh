#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/module-cache"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache" \
swift build -c release --disable-sandbox

DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Zebtron Camera zapper - automated backup.app"
STAGE_ROOT="$(mktemp -d /tmp/camera-zapper-build.XXXXXX)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
APP_DIR="$STAGE_ROOT/$APP_NAME"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$ROOT_DIR/.build/release/CameraBackup" "$BIN_DIR/CameraBackup"
cp "$ROOT_DIR/Resources/CameraZapper.icns" "$RES_DIR/CameraZapper.icns"
cp "$ROOT_DIR/Sources/CameraBackup/Resources/camera-default.png" "$RES_DIR/camera-default.png"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CameraBackup</string>
<key>CFBundleIdentifier</key><string>com.zebtron.CameraZapper</string>
<key>CFBundleName</key><string>Zebtron Camera zapper</string>
<key>CFBundleDisplayName</key><string>Zebtron Camera zapper - automated backup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.346</string>
<key>CFBundleVersion</key><string>1346</string>
<key>CFBundleIconFile</key><string>CameraZapper.icns</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Zebtron. All rights reserved.</string>
<key>NSRemovableVolumesUsageDescription</key><string>Camera Zapper needs access to camera cards to scan and back up your media.</string>
<key>NSNetworkVolumesUsageDescription</key><string>Camera Zapper copies and verifies media on NAS shares selected by the user.</string>
<key>NSDocumentsFolderUsageDescription</key><string>Camera Zapper stores verified archives in the folders you choose.</string>
<key>NSAppleEventsUsageDescription</key><string>Camera Zapper uses Apple Events to import explicitly selected, verified media into Apple Photos and supported catalog applications.</string>
<key>NSPhotoLibraryAddUsageDescription</key><string>Camera Zapper adds media you explicitly back up to your Apple Photos library.</string>
</dict></plist>
PLIST

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

mkdir -p "$DIST_DIR"
ditto "$APP_DIR" "$DIST_DIR/$APP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/Zebtron-Camera-Zapper-1.346-App.zip"
hdiutil create -volname "Zebtron Camera Zapper 1.346" -srcfolder "$APP_DIR" -ov -format UDZO "$DIST_DIR/Zebtron-Camera-Zapper-1.346.dmg" >/dev/null
echo "$DIST_DIR/$APP_NAME"
echo "$DIST_DIR/Zebtron-Camera-Zapper-1.346-App.zip"
echo "$DIST_DIR/Zebtron-Camera-Zapper-1.346.dmg"
