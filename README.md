# 轻图 (LiteImage)

macOS 图片压缩 & 格式转换工具，支持 PNG / JPG 无损压缩，以及视频转 GIF。

![Platform](https://img.shields.io/badge/Platform-macOS%2013.0+-orange)
![Swift](https://img.shields.io/badge/Swift-5.9-blue)
![License](https://img.shields.io/badge/License-MIT-green)

[English](./README_en.md) · [中文](./README.md)

---

## 1. 介绍

**轻图** 是一款 macOS 原生图片压缩工具，提供两种压缩引擎：

| 引擎 | 工具链 | 说明 |
|------|--------|------|
| **本地引擎** | Posterizer + oxipng | 离线压缩、真彩色保留、速度取决于 Mac 性能 |
| **TinyPNG 云端** | TinyPNG API | 压缩率极高，需要网络，每月 500 张免费额度 |

此外支持 **格式转换**（PNG ↔ JPG）和 **视频转 GIF**（ffmpeg + gifski）。

---

## 2. 用法

### 系统要求

- macOS 13.0 及以上
- Apple Silicon 或 Intel Mac
- 可选：TinyPNG API Key（[免费申请](https://tinypng.com/developers)，每月 500 张额度）

### 安装

1. 下载最新 Release 版本
2. 将 `轻图.app` 拖入 Applications 文件夹
3. 首次启动可能需要在「系统设置 → 隐私与安全性」中允许运行

---

## 3. 功能

### 图片压缩

- PNG / JPG 双格式支持
- **TinyPNG 云端** + **本地引擎** 自动切换（高质量走云端、中等质量走本地）
- **三档质量**：不压缩 / 中等质量 / 高质量
- **格式转换**：PNG → JPG、JPG → PNG，每张独立设置
- **列表管理模式**：拖入图片先进入列表，可逐张设置格式、质量、缩放后再一键压缩
- **按长边等比缩放**：每项独立设置，支持自定义像素及快捷预设（1920 / 1280 / 800）
- **覆盖/副本模式**：可选覆盖原文件或保存 `xxx-compressed.xxx`
- **压缩记录日志**：实时显示成功/失败统计
- **Debug 日志**：可开关，写入 `~/Library/Logs/LiteImage/`，含完整工具调用参数

### 视频转 GIF

- gifski 高质量编码 + 精简版 ffmpeg 提取帧
- **三档质量预设**：低 / 中 / 高
- 可调节宽度（160-1280px）和帧率（5-30 FPS）
- 批量转换，实时日志

### 其他

- **多语言**：自动跟随系统（简体中文 / English）
- **原生体验**：SwiftUI 构建
- **安全**：本地引擎完全离线，不上传文件

---

## 4. 本地压缩技术栈

| 步骤 | 工具 | 说明 |
|------|------|------|
| 1 | **Posterizer** v2.1 | 中值切割预量化，温和减色保真 |
| 2 | **oxipng** v10.2.0 | 无损 deflate 优化，level 6 最高压缩 |
| 3 | **TinyPNG** | 高质量档位自动走云端（需 API Key） |

---

## 5. 鸣谢

本项目使用了以下开源项目：

| 项目 | 用途 | 链接 |
|------|------|------|
| **Posterizer** | PNG 预量化 | https://github.com/kornelski/mediancut-posterizer |
| **oxipng** | PNG 无损优化 | https://github.com/shssoichiro/oxipng |
| **Gifski** | GIF 高质量编码 | https://github.com/imageoptim/gifski |
| **TinyPNG** | 云端图片压缩 API | https://tinypng.com/ |
| **ffmpeg** | 视频帧提取（精简版） | https://github.com/ffmpeg/ffmpeg |

---

## 6. 特别声明

作者是一名设计师，完全 0 代码基础，本项目方便在日常工作中使用。所有代码均由 AI（Deepseek、智谱 GLM）生成，App Icon 也是 AI 制作的。

有问题请提交 [Issues](https://github.com/Ziloong/Liteimage/issues)。

---

## 更新日志

详见 [CHANGELOG.md](./CHANGELOG.md)

## License

MIT License
