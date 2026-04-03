#!/bin/bash
set -e

APP_NAME="IslandDrop"
BUNDLE_ID="com.islanddrop.app"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR="dist/dmg"

echo "==> 清理旧构建..."
rm -rf dist
mkdir -p dist

echo "==> 编译 Release..."
swift build -c release 2>&1

echo "==> 创建 .app 包结构..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 复制二进制
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 复制 Info.plist
cp "IslandDrop/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# 复制资源包（SPM 生成的 bundle）
if [ -d "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi

# 创建 PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# 签名（ad-hoc，本地使用无需开发者证书）
echo "==> 签名 .app..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> 创建 DMG..."
mkdir -p "${DMG_DIR}"

# 复制 .app 到 DMG 临时目录
cp -R "${APP_BUNDLE}" "${DMG_DIR}/"

# 创建 Applications 快捷方式
ln -sf /Applications "${DMG_DIR}/Applications"

# 创建 DMG
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    "dist/${DMG_NAME}"

# 清理临时目录
rm -rf "${DMG_DIR}"

echo ""
echo "==> 构建完成!"
echo "    .app: ${APP_BUNDLE}"
echo "    .dmg: dist/${DMG_NAME}"
echo ""
echo "    安装: 打开 DMG，拖拽 ${APP_NAME} 到 Applications"
