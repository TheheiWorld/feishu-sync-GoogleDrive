#!/bin/bash
#
# IslandDrop 编译打包脚本
# 用法:
#   ./scripts/build.sh                  # 默认 release 编译 + 生成 .app
#   ./scripts/build.sh --dmg            # 额外生成 DMG 安装包
#   ./scripts/build.sh --debug          # Debug 编译（不生成 DMG）
#   ./scripts/build.sh --clean          # 清理所有构建产物
#   ./scripts/build.sh --sign <identity> # 使用指定证书签名（默认 ad-hoc）
#
set -euo pipefail

# ─── 配置 ────────────────────────────────────────────────────────────────────
APP_NAME="IslandDrop"
BUNDLE_ID="com.islanddrop.app"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
SOURCE_DIR="${PROJECT_DIR}/IslandDrop"
INFO_PLIST="${SOURCE_DIR}/Info.plist"
ENTITLEMENTS="${SOURCE_DIR}/IslandDrop.entitlements"

# 从 Info.plist 读取版本号
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}" 2>/dev/null || echo "1.0.0")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST}" 2>/dev/null || echo "1")

# 默认参数
CONFIG="release"
MAKE_DMG=false
CLEAN_ONLY=false
SIGN_IDENTITY="-"  # ad-hoc

# ─── 参数解析 ─────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            CONFIG="debug"
            shift
            ;;
        --dmg)
            MAKE_DMG=true
            shift
            ;;
        --clean)
            CLEAN_ONLY=true
            shift
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --debug          Debug 编译（默认 Release）"
            echo "  --dmg            生成 DMG 安装包"
            echo "  --clean          清理所有构建产物"
            echo "  --sign <identity> 代码签名身份（默认 ad-hoc）"
            echo "  -h, --help       显示帮助"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

BUILD_DIR="${PROJECT_DIR}/.build/${CONFIG}"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

# ─── 辅助函数 ─────────────────────────────────────────────────────────────────
step() {
    echo ""
    echo "==> $1"
}

# ─── 清理 ─────────────────────────────────────────────────────────────────────
if $CLEAN_ONLY; then
    step "清理构建产物..."
    rm -rf "${DIST_DIR}"
    rm -rf "${PROJECT_DIR}/.build"
    echo "    已清理 dist/ 和 .build/"
    exit 0
fi

# ─── 编译 ─────────────────────────────────────────────────────────────────────
step "编译 ${APP_NAME} (${CONFIG})..."
cd "${PROJECT_DIR}"
swift build -c "${CONFIG}" 2>&1

if [ ! -f "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "错误: 编译产物不存在: ${BUILD_DIR}/${APP_NAME}"
    exit 1
fi

# ─── 创建 .app Bundle ────────────────────────────────────────────────────────
step "创建 ${APP_NAME}.app 包结构..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 复制可执行文件
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 复制 Info.plist
cp "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"

# 复制 SPM 资源 bundle
RESOURCE_BUNDLE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
    echo "    已复制资源 bundle"
fi

# 处理 App Icon（从 xcassets 中提取 icns）
ICONSET_DIR="${SOURCE_DIR}/Assets.xcassets/AppIcon.appiconset"
if [ -d "${ICONSET_DIR}" ]; then
    # 检查是否有 png 图标文件
    ICON_COUNT=$(find "${ICONSET_DIR}" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${ICON_COUNT}" -gt 0 ]; then
        step "生成应用图标..."
        TEMP_ICONSET=$(mktemp -d)/AppIcon.iconset
        mkdir -p "${TEMP_ICONSET}"

        # 复制 png 文件到 iconset 目录
        for png in "${ICONSET_DIR}"/*.png; do
            [ -f "$png" ] && cp "$png" "${TEMP_ICONSET}/"
        done

        # 转换为 icns
        if iconutil -c icns "${TEMP_ICONSET}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" 2>/dev/null; then
            # 在 Info.plist 中设置图标
            /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || \
            /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${APP_BUNDLE}/Contents/Info.plist"
            echo "    已生成 AppIcon.icns"
        else
            echo "    警告: 图标生成失败，跳过"
        fi

        rm -rf "$(dirname "${TEMP_ICONSET}")"
    fi
fi

# 创建 PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# ─── 代码签名 ─────────────────────────────────────────────────────────────────
step "代码签名..."
if [ -f "${ENTITLEMENTS}" ]; then
    codesign --force --deep --options runtime \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${SIGN_IDENTITY}" \
        "${APP_BUNDLE}"
    echo "    已使用 entitlements 签名"
else
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
    echo "    已签名（无 entitlements）"
fi

# 验证签名
codesign --verify --verbose "${APP_BUNDLE}" 2>&1 || echo "    警告: 签名验证失败"

# ─── 构建信息 ─────────────────────────────────────────────────────────────────
APP_SIZE=$(du -sh "${APP_BUNDLE}" | cut -f1)
step "构建信息:"
echo "    应用: ${APP_BUNDLE}"
echo "    版本: ${VERSION} (${BUILD_NUMBER})"
echo "    配置: ${CONFIG}"
echo "    大小: ${APP_SIZE}"
echo "    签名: ${SIGN_IDENTITY}"

# ─── 生成 DMG ─────────────────────────────────────────────────────────────────
if $MAKE_DMG; then
    DMG_NAME="${APP_NAME}-${VERSION}.dmg"
    DMG_PATH="${DIST_DIR}/${DMG_NAME}"
    DMG_TEMP="${DIST_DIR}/dmg-staging"

    step "生成 DMG 安装包..."
    rm -rf "${DMG_TEMP}"
    mkdir -p "${DMG_TEMP}"

    # 复制 .app
    cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"

    # 创建 Applications 快捷方式
    ln -sf /Applications "${DMG_TEMP}/Applications"

    # 创建 DMG
    hdiutil create \
        -volname "${APP_NAME}" \
        -srcfolder "${DMG_TEMP}" \
        -ov \
        -format UDZO \
        "${DMG_PATH}"

    rm -rf "${DMG_TEMP}"

    DMG_SIZE=$(du -sh "${DMG_PATH}" | cut -f1)
    echo "    DMG: ${DMG_PATH} (${DMG_SIZE})"
fi

# ─── 完成 ─────────────────────────────────────────────────────────────────────
step "构建完成!"
echo ""
echo "    运行: open ${APP_BUNDLE}"
if $MAKE_DMG; then
    echo "    安装: 打开 DMG，将 ${APP_NAME} 拖入 Applications"
fi
echo ""
