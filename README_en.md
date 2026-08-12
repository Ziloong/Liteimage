# LiteImage

macOS image compression & conversion tool. Supports PNG / JPG lossless optimization and video to GIF conversion.

![Platform](https://img.shields.io/badge/Platform-macOS%2013.0+-orange)
![Swift](https://img.shields.io/badge/Swift-5.9-blue)
![License](https://img.shields.io/badge/License-MIT-green)

[中文](./README.md) · [English](./README_en.md)

---

## 1. Overview

**LiteImage** is a native macOS image optimization tool with dual engines:

| Engine | Toolchain | Notes |
|--------|-----------|-------|
| **Local** | Posterizer + oxipng | Offline, true-color output, speed depends on Mac |
| **TinyPNG Cloud** | TinyPNG API | Extreme compression, requires internet, 500 free/month |

Also supports **format conversion** (PNG ↔ JPG) and **video to GIF** (ffmpeg + gifski).

---

## 2. Usage

### Requirements

- macOS 13.0+
- Apple Silicon or Intel Mac
- Optional: TinyPNG API Key ([free signup](https://tinypng.com/developers), 500 credits/month)

### Install

1. Download the latest Release
2. Drag `LiteImage.app` to Applications
3. First launch may require approval in System Settings → Privacy & Security

---

## 3. Features

### Image Compression

- PNG / JPG support
- **TinyPNG Cloud** + **Local Engine** auto-switching (High quality → cloud, Medium → local)
- **3 quality tiers**: None / Medium / High
- **Format conversion**: PNG → JPG, JPG → PNG (per-image setting)
- **Batch list mode**: drag images into a list, configure each individually, then compress all at once
- **Resize by long edge**: per-image toggle with presets (1920 / 1280 / 800 px)
- **Overwrite / Save-as mode**
- **Compression logs**: real-time stats
- **Debug log**: toggle in Settings, writes to `~/Library/Logs/LiteImage/`

### Video to GIF

- gifski high-quality encoding + lightweight ffmpeg frame extraction
- **3 quality presets**: Low / Medium / High
- Adjustable width (160-1280px) and framerate (5-30 FPS)
- Batch conversion

### Other

- **i18n**: Simplified Chinese / English (auto follows system)
- **Native UI**: SwiftUI
- **Secure**: local engine works fully offline

---

## 4. Local Compression Pipeline

| Step | Tool | Description |
|------|------|-------------|
| 1 | **Posterizer** v2.1 | Median-cut pre-quantization, gentle color reduction |
| 2 | **oxipng** v10.2.0 | Lossless deflate optimization, level 6 max compression |
| 3 | **TinyPNG** | High quality tier auto-uses cloud API |

---

## 5. Credits

| Project | Purpose | Link |
|---------|---------|------|
| **Posterizer** | PNG pre-quantizer | https://github.com/kornelski/mediancut-posterizer |
| **oxipng** | PNG lossless optimizer | https://github.com/shssoichiro/oxipng |
| **Gifski** | GIF encoder | https://github.com/imageoptim/gifski |
| **TinyPNG** | Cloud compression API | https://tinypng.com/ |
| **ffmpeg** | Video frame extraction | https://github.com/ffmpeg/ffmpeg |

---

## Changelog

See [CHANGELOG.md](./CHANGELOG.md)

## License

MIT License
