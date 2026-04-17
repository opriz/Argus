#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Argus"
DMG_NAME="Argus"
BUILD_DIR="build"

# ─── Step 1: Build Release ───
echo "Building Release..."
if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -scheme "${APP_NAME}" -configuration Release \
        -derivedDataPath "${BUILD_DIR}" \
        -skipPackagePluginValidation \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE="Manual" \
        DEVELOPMENT_TEAM=""
elif [ -d "${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app" ]; then
    echo "Using existing Release build..."
else
    echo "未找到 xcodebuild，也没有现有 Release build。"
    echo "请在 Xcode 里手动编译 Release："
    echo "  Product -> Build For -> Profiling"
    exit 1
fi

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
    echo "Error: 找不到 ${APP_PATH}"
    exit 1
fi

# ─── Step 2: Re-sign with ad-hoc (remove your personal cert) ───
echo "Re-signing app..."
codesign --sign - --force --deep "${APP_PATH}"

# ─── Step 3: Create DMG with styled Finder window ───
RW_DMG=".staging_rw.dmg"
rm -f "${RW_DMG}" "${DMG_NAME}.dmg"

# Create a blank read-write DMG
APP_SIZE=$(du -sm "${APP_PATH}" | cut -f1)
SIZE_MB=$((APP_SIZE + 40))
hdiutil create -size "${SIZE_MB}m" -fs HFS+ -volname "${DMG_NAME}" -type UDIF "${RW_DMG}"

# Mount it read-write
echo "Mounting staging DMG..."
MOUNT_INFO=$(hdiutil attach "${RW_DMG}" -readwrite -nobrowse -noverify -noautoopen)
MOUNT_DEV=$(echo "$MOUNT_INFO" | grep "Apple_HFS" | awk '{print $1}')
MOUNT_POINT=$(echo "$MOUNT_INFO" | grep "Apple_HFS" | awk '{print $3}')

for i in {1..10}; do
    if [ -d "${MOUNT_POINT}" ]; then break; fi
    sleep 0.3
done

# Copy app and create Applications shortcut
# Use ditto to avoid xattr copy issues
ditto "${APP_PATH}" "${MOUNT_POINT}/${APP_NAME}.app"
ln -s /Applications "${MOUNT_POINT}/Applications"

# ─── Step 4: Style the Finder window ───
echo "Styling DMG window..."
osascript <<EOF
tell application "Finder"
    tell disk "${DMG_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 560, 420}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set text size of viewOptions to 12
        set background color of viewOptions to {65535, 65535, 65535}
        set position of item "${APP_NAME}.app" to {120, 170}
        set position of item "Applications" to {360, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Sync and unmount
sync
hdiutil detach "${MOUNT_DEV}" -force

# ─── Step 5: Convert to compressed read-only DMG ───
echo "Creating final DMG..."
hdiutil convert "${RW_DMG}" -format UDZO -ov -o "${DMG_NAME}.dmg"

# ─── Cleanup ───
rm -f "${RW_DMG}"

echo ""
echo "✅ 打包完成: $(realpath ${DMG_NAME}.dmg)"
echo ""
echo "分发说明:"
echo "1. 用户下载后双击 .dmg，把 .app 拖到 Applications"
echo "2. 首次打开需要 右键 -> 打开 (因为未公证)"
echo "3. 如果有开发者账号，用 'Product -> Archive -> Distribute App' 做正式分发"
