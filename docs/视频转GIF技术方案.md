# 视频转 GIF 技术方案

## 概述

轻图（LiteImage）使用 **ffmpeg + gifski** 实现视频转 GIF 功能，分为视频帧提取和 GIF 合成两个步骤。

---

## 工具说明

| 工具 | 用途 | 在项目中的角色 |
|------|------|--------------|
| **ffmpeg** | 从视频中提取帧 | 负责解码视频、输出 PNG 图片序列 |
| **gifski** | 将图片序列合成为 GIF | 负责高质量 GIF 编码和颜色优化 |

gifski 是目前公认质量最高的 GIF 编码器，基于 libimagequant 调色板算法，远优于 ffmpeg 内置的 GIF 编码器。

---

## 处理流程

```
原始视频 (MP4/MOV/M4V)
    │
    ▼
┌─────────────────────────────────────────┐
│  Step 1: ffmpeg 提取帧                    │
│                                         │
│  ffmpeg -i input.mp4                    │
│    -vf "fps=<帧率>,scale=<宽度>:-1"      │
│    -q:v 1                               │
│    frame%04d.png                         │
└─────────────────────────────────────────┘
    │
    ▼
PNG 序列 (frame0001.png, frame0002.png ...)
    │
    ▼
┌─────────────────────────────────────────┐
│  Step 2: gifski 合成 GIF                 │
│                                         │
│  gifski -Q <质量> -W <宽度> -r <帧率>   │
│    -o output.gif                        │
│    frame*.png                            │
└─────────────────────────────────────────┘
    │
    ▼
最终 GIF 文件
```

---

## 参数说明

### ffmpeg 参数

| 参数 | 作用 | 示例值 |
|------|------|--------|
| `-i input` | 输入视频 | `-i video.mp4` |
| `-vf "fps=X"` | 按指定帧率提取 | `-vf "fps=15"` |
| `-vf "scale=W:-1"` | 按宽度缩放，高度等比 | `-vf "scale=480:-1"` |
| `-q:v 1` | 输出 PNG 质量（1最高） | `-q:v 1` |
| `frame%04d.png` | 输出文件名格式 | `frame%04d.png` |

### gifski 参数

| 参数 | 作用 | 范围/示例 |
|------|------|----------|
| `-Q <n>` | 质量（1-100） | 低=50, 中=70, 高=90 |
| `-W <n>` | 输出宽度（像素） | 160-1280 |
| `-r <n>` | 帧率（每秒帧数） | 5-30 |
| `-o <file>` | 输出文件 | `-o output.gif` |
| `frame*.png` | 输入帧文件（支持通配符） | `frame*.png` |

---

## 三档质量预设

| 档位 | gifski -Q | ffmpeg fps | ffmpeg scale | 效果 |
|------|-----------|------------|--------------|------|
| 低 | 50 | 10 | 320px | 最小体积，动画感强 |
| 中 | 70 | 15 | 480px | 平衡体积和质量 |
| 高 | 90 | 20 | 640px | 最佳清晰度，体积较大 |

---

## macOS 版二进制

轻图 macOS 版使用预编译的 gifski 二进制：
- 路径：`LiteImage.app/Contents/Resources/gifski`
- 来源：从 gifski 官网或通过 `cargo install gifski` 编译
- 运行时从 `Bundle.main.resourcePath` 获取路径

```swift
private var gifskiPath: String {
    Bundle.main.resourcePath.map { "\($0)/gifski" } ?? ""
}
```

---

## Windows 版二进制

轻图 Windows 版（Tauri）使用交叉编译的精简版 ffmpeg：

### 为什么需要精简版？
完整 ffmpeg 体积约 96MB，对于桌面应用来说太大。精简版仅保留核心功能：

| 功能 | 说明 |
|------|------|
| 视频解码 | h264, hevc, vp8, vp9 等主流格式 |
| PNG 编码 | 输出帧序列 |
| scale 滤镜 | 等比缩放 |
| fps 滤镜 | 帧率控制 |

**最终体积：约 5.4 MB**

### 编译方式（macOS 交叉编译 Windows x64）

```bash
# 1. 安装 mingw-w64 交叉编译工具链
brew install mingw-w64

# 2. 编译 zlib（ffmpeg 依赖）
./configure --prefix=/usr/local/zlib-mingw \
    --cross-prefix=x86_64-w64-mingw32- \
    --static
make && make install

# 3. 编译 ffmpeg（精简配置）
export CC="x86_64-w64-mingw32-gcc"
export PKG_CONFIG_PATH="/usr/local/zlib-mingw/lib/pkgconfig"

./configure \
    --target-os=mingw32 \
    --cross-prefix=x86_64-w64-mingw32- \
    --arch=x86_64 \
    --enable-gpl \
    --disable-doc \
    --disable-programs \
    --disable-devices \
    --disable-avdevice \
    --disable-avfilter \
    --disable-doc \
    --disable-network \
    --disable-everything \
    --enable-libpng \
    --enable-decoder=h264,hevc,vp8,vp9 \
    --enable-encoder=png \
    --enable-filter=scale,fps \
    --extra-cflags="-I/usr/local/zlib-mingw/include" \
    --extra-ldflags="-L/usr/local/zlib-mingw/lib"

make -j$(nproc)
x86_64-w64-mingw32-strip ffmpeg.exe
```

### Windows 端二进制路径（Tauri）

```rust
// src-tauri/tauri.conf.json 或代码中指定
let ffmpeg_path = app.path().resource_dir() + "/ffmpeg.exe";
```

---

## GIF 压缩功能

GIF 压缩直接用 gifski 重新编码已有 GIF，无需 ffmpeg：

```bash
gifski -Q <质量> -W <宽度> -o output_compressed.gif input.gif
```

gifski 会：
1. 解码原 GIF 的每一帧
2. 重新生成最优调色板
3. 输出更小体积的 GIF

---

## 相关代码

- **GIFConverterViewModel.swift**：视频转 GIF 主逻辑
- **LocalCompressorService.swift**：gifski 压缩 GIF 逻辑
- **binaries/ffmpeg**（macOS 版）：视频帧提取
- **binaries/gifski**：GIF 合成与压缩

---

## 参考链接

- gifski 官网：https://gif.ski/
- gifski GitHub：https://github.com/imageoptim/gifski
- ffmpeg 官网：https://ffmpeg.org/
