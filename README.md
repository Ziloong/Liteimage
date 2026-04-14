# 轻图 (LiteImagePng)

macOS 图片压缩工具，支持 PNG / JPG / GIF 无损压缩，以及视频转 GIF 功能。

![Platform](https://img.shields.io/badge/Platform-macOS%2012.0+-orange)
![Swift](https://img.shields.io/badge/Swift-5.9-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 1. 介绍

**轻图** 是一款 macOS 原生图片压缩工具，提供两种压缩引擎：

| 引擎 | 说明 | 优势 |
|------|------|------|
| **TinyPNG 云端** | 调用 TinyPNG API 进行压缩 | 压缩率高，支持 PNG 24-bit 透明通道 |
| **本地引擎** | 使用 pngquant / gifsicle 进行本地压缩 | 无需网络，完全离线 |

此外还支持 **视频转 GIF** 功能，基于 gifski + ffmpeg 实现高质量转换。

---

## 2. 用法

### 系统要求

- macOS 12.0 及以上
- 可选：TinyPNG API Key（[免费申请](https://tinypng.com/developers)，每月 500 张额度）

### 安装

1. 下载最新 Release 版本
2. 将 `轻图.app` 拖入 Applications 文件夹
3. 首次启动可能需要在「系统设置 → 隐私与安全性」中允许运行

---

## 3. 特征

### 图片压缩

- PNG / JPG / GIF 三种格式支持
- TinyPNG 云端压缩 + 本地引擎双模式
- 实时显示压缩统计（已压缩张数、节省空间、平均压缩率）
- 可选覆盖原文件或保存副本
- 压缩记录日志

### 视频转 GIF

- 基于 gifski 高质量编码
- 精简版 ffmpeg 提取视频帧（App 体积仅 4.6MB）
- 质量预设：低 / 中 / 高三档
- 可调节宽度和帧率
- 实时转换日志

### 其他

- **多语言**：自动跟随系统语言（简体中文 / English）
- **原生体验**：SwiftUI 构建，流畅响应
- **安全**：所有压缩在本地完成，不上传用户文件（除 TinyPNG 模式需网络）

---

## 4. 鸣谢

本项目使用了以下开源项目：

| 项目 | 用途 | 链接 |
|------|------|------|
| **pngquant** | PNG 图片本地压缩 | https://pngquant.org/ |
| **Gifski** | 高质量 GIF 编码 | https://github.com/imageoptim/gifski |
| **TinyPNG** | 云端图片压缩 API | https://tinypng.com/ |
| **ffmpeg** | 视频帧提取（精简版） | https://github.com/ffmpeg/ffmpeg |

---
## 5. 特别声明
作者是一名设计师，完全0代码基础，本项目是方便在日常工作中使用，所有代码均由Agent生产，其中用到的Model有Deepseek3.2、智谱GLM5.X，有问题请提交lssues


## License

MIT License
