#!/bin/bash

set -e

APP_NAME="轻图png"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "📦 构建 ${APP_NAME}..."

# 清理旧构建
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# 创建 App Bundle 目录结构
echo "📁 创建 App Bundle 结构..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 编译 Swift 代码
echo "🔨 编译 Swift 代码..."

swift build -c release 2>/dev/null || {
    echo "⚠️  swift build 失败，使用 swiftc 直接编译..."
    
    # 收集所有 Swift 文件
    SWIFT_FILES=$(find Sources -name "*.swift" | tr '\n' ' ')
    
    swiftc \
        -O \
        -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" \
        -framework Foundation \
        -framework SwiftUI \
        -framework AppKit \
        -framework Combine \
        -target arm64-apple-macos13.0 \
        ${SWIFT_FILES}
}

# 如果 swift build 成功，复制可执行文件
if [ -f ".build/release/轻图png" ]; then
    cp ".build/release/轻图png" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
fi

# 创建 Info.plist
echo "📝 创建 Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>轻图png</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.ziloong.轻图png</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>轻图png</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 如果有图标文件，复制到 Resources
if [ -f "AppIcon.icns" ]; then
    echo "🎨 复制图标..."
    cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
fi

# 设置可执行权限
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo ""
echo "✅ 构建完成！"
echo "   App 路径：${APP_BUNDLE}"
echo ""
echo "🚀 运行方式："
echo "   1. 双击 ${APP_BUNDLE} 运行"
echo "   2. 或在终端执行：open '${APP_BUNDLE}'"
