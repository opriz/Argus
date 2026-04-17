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
        DEVELOPMENT_TEAM="" \
        archivePath="${BUILD_DIR}/${APP_NAME}.xcarchive" \
        archive

    # Export from archive
    xcodebuild -exportArchive \
        -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
        -exportPath "${BUILD_DIR}/Release" \
        -exportOptionsPlist /dev/stdin <<EOF
{
    "method": "developer-id",
    "signingStyle": "manual",
    "stripSwiftSymbols": true,
    "thinning": "<none>"
}
EOF
elif [ -d "${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app" ]; then
    echo "Using existing Release build..."
    mkdir -p "${BUILD_DIR}/Release"
    cp -R "${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app" "${BUILD_DIR}/Release/"
else
    echo "未找到 xcodebuild，也没有现有 Release build。"
    echo "请在 Xcode 里手动编译 Release："
    echo "  Product -> Build For -> Profiling"
    exit 1
fi

APP_PATH="${BUILD_DIR}/Release/${APP_NAME}.app"

# ─── Step 2: Re-sign with ad-hoc (remove your personal cert) ───
echo "Re-signing app..."
codesign --sign - --force --deep "${APP_PATH}"

# ─── Step 3: Create DMG staging ───
STAGING=".dmg_staging"
rm -rf "${STAGING}" "${DMG_NAME}.dmg"
mkdir -p "${STAGING}"
cp -R "${APP_PATH}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

# ─── Step 4: Build DMG ───
echo "Creating DMG..."
hdiutil create \
    -volname "${DMG_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "${DMG_NAME}.dmg"

# ─── Cleanup ───
rm -rf "${STAGING}"

echo ""
echo "✅ 打包完成: $(realpath ${DMG_NAME}.dmg)"
echo ""
echo "分发说明:"
echo "1. 用户下载后双击 .dmg，把 .app 拖到 Applications"
echo "2. 首次打开需要 右键 -> 打开 (因为未公证)"
echo "3. 如果有开发者账号，用 'Product -> Archive -> Distribute App' 做正式分发"
