# 轻图 Windows 版

Windows 版本的轻图图片压缩工具，使用 Python + tkinter 构建。

## 系统要求

- Windows 10 / 11
- Python 3.9+

## 快速开始

### 1. 安装 Python

从 https://www.python.org/downloads/ 下载安装（勾选 "Add Python to PATH"）

### 2. 安装依赖

```cmd
cd windows
pip install -r requirements.txt
```

### 3. 运行

```cmd
python main.py
```

或者双击 `main.py`（如果 Python 关联了 .py 文件）。

## 功能

- 图片压缩：Posterizer + oxipng 本地引擎，TinyPNG 云端
- 格式转换：PNG ↔ JPG
- 质量档位：不压缩 / 中等质量 / 高质量
- 按长边缩放
- 覆盖/副本模式
- Debug 日志

## 工具

| 工具 | 文件 | 来源 |
|------|------|------|
| oxipng | tools/oxipng.exe | https://github.com/shssoichiro/oxipng |
| posterize | tools/posterize.exe | https://github.com/kornelski/mediancut-posterizer |

## 打包成 EXE（可选）

```cmd
pip install pyinstaller
pyinstaller --onefile --windowed --add-data "tools;tools" main.py
```

生成的 `dist/main.exe` 可直接发给用户，无需安装 Python。
