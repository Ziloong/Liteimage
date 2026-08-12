# 轻图 (LiteImage) 项目记忆

## 项目概述
- **macOS 版**：`/Users/ziloong/Documents/轻图png/` — Swift/SwiftUI 原生应用
- **Windows 版**：`/Users/ziloong/Documents/轻图png-windows/` — Tauri v2 + React 跨平台移植
- **目标**：图片压缩（PNG/JPG/GIF）+ 视频转 GIF，支持本地引擎（pngquant/gifski/ffmpeg）和 TinyPNG API

## Windows 版技术栈
- **后端**：Rust + Tauri v2，命令行工具调用（pngquant、gifski、ffmpeg、ffprobe）
- **前端**：React 18 + TypeScript + Vite 5，纯手写 CSS
- **工具二进制**：需放入 `src-tauri/resources/`，随应用打包

## Windows 开发环境
- Windows VM IP: 192.168.124.13, 用户 Ziloong, 密码 123123
- macOS 局域网 IP: 192.168.124.24
- macOS 代理: 127.0.0.1:7890（仅本地监听，VM 无法访问）
- **Windows VM 代理: 127.0.0.1:7890**（需设置 `$env:HTTP_PROXY` 和 `$env:HTTPS_PROXY`）
- Parallels 网络 IP 10.211.55.x 已不通（VM 使用 WLAN）
- 已安装: Node.js v24.14.0, Rust 1.95.0, npm
- SSH 连接: `sshpass -p '123123' ssh Ziloong@192.168.124.13`（默认 PowerShell）
- 文件同步: 用 `tar czf | ssh tar xzf`（rsync/scp 在 Windows 不可用）
- macOS tar 会生成 `._*` Apple Double 文件，同步到 Windows 后需清理
- **Windows 项目目录是 `LiteImage-Windows`，不是 `轻图png-windows`**
- 工具链: pngquant 2.17.0, gifski 1.34.0, ffmpeg 8.1

## 质量分级
- PNG ultraLow 10-20, low 40-60, medium 65-80, high 85-95
- JPG: 转 PNG + pngquant 压缩

## 构建步骤（Windows）
1. 将工具二进制放入 `src-tauri/resources/`
2. `npm install`
3. 设置代理: `$env:HTTP_PROXY='http://127.0.0.1:7890'; $env:HTTPS_PROXY='http://127.0.0.1:7890'`
4. `npm run tauri build`
5. **便携式 exe**：`tauri.conf.json` 中 `bundle.targets` 设为 `[]`，只生成 exe 不生成 MSI/NSIS
6. 编译后需手动 `Copy-Item -Recurse resources target/release/resources` 把工具放到 exe 旁边
7. exe 路径：`src-tauri/target/release/liteimage.exe`

## Windows 构建踩坑记录
- Cargo.toml 不应包含 `[lib]` 段（除非有 lib.rs），否则编译报错
- icon.ico 必须是真正的 ICO 格式，PNG 伪装的 .ico 会导致 RC 编译失败
- base64 v0.22 需要显式 `use base64::Engine;` 才能用 encode/decode
- `unwrap_or(PathBuf::from(...))` 返回类型不匹配，应用 `unwrap_or_else(|| Path::new(...))`
- MSI 打包需要下载 WiX 和 NSIS，必须设置代理 `$env:HTTPS_PROXY`
- WiX 3.14 默认 code page 1252 不支持中文，productName 必须用英文
- tauri.conf.json 中 productName 已改为 "LiteImage"，title 改为 "LiteImage"
- Tauri v2 的 `bundle.targets` 不支持 `"none"`，应用空数组 `[]`
- 隐藏 CMD 窗口：`CommandExt::creation_flags(0x08000000)` 即 `CREATE_NO_WINDOW`
- 异步压缩：`compress_image`/`convert_video_to_gif` 改为 `async fn`，用 `tokio::task::spawn_blocking` 包裹耗时操作
- 用户只需要便携式 exe，不需要 MSI/NSIS 安装包
