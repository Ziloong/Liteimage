#!/bin/bash

set -e

echo "📦 构建 TinyPNG Compressor (SwiftUI)..."

# 创建输出目录
mkdir -p build

# 编译 Swift 文件
echo "🔨 编译 Swift 代码..."

swiftc \
    -O \
    -o "build/TinyPNG Compressor" \
    -framework Foundation \
    -framework SwiftUI \
    -framework AppKit \
    -framework Combine \
    -target arm64-apple-macos13.0 \
    TinyPNG\ Compressor/*.swift

echo "✅ 构建完成！"
echo "   可执行文件：build/TinyPNG Compressor"