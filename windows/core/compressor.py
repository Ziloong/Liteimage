"""压缩引擎 — Posterizer + oxipng + TinyPNG"""

import subprocess
import os
import sys
import shutil
import logging
from PIL import Image
import requests

logger = logging.getLogger("LiteImage")


def _resource_dir():
    """资源目录（tools/ 的父目录），兼容 PyInstaller 打包"""
    if getattr(sys, "frozen", False):
        # 打包后：数据解压到 sys._MEIPASS
        return sys._MEIPASS
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


TOOLS_DIR = os.path.join(_resource_dir(), "tools")

# 进程跟踪（支持停止按钮）
_current_process = None


def terminate():
    """强制终止当前正在运行的子进程"""
    global _current_process
    if _current_process and _current_process.poll() is None:
        logger.info("⏹ 用户停止，终止进程...")
        _current_process.kill()
        _current_process = None


def _run_tracked(cmd):
    """运行命令，支持外部 kill"""
    global _current_process
    logger.info(f"▶ {' '.join(cmd)}")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    _current_process = proc
    try:
        stdout, stderr = proc.communicate()
        if proc.returncode != 0:
            raise subprocess.CalledProcessError(proc.returncode, cmd, stdout, stderr)
        return stdout
    finally:
        _current_process = None


def _tool_path(name):
    return os.path.join(TOOLS_DIR, name)


def posterize(input_path, output_path, quality=80):
    """Posterizer 预量化（v2.1，-b blurize 模式推荐，-d 抖动会增大体积故不用）"""
    exe = _tool_path("posterize.exe")
    if not os.path.exists(exe):
        logger.warning("posterize.exe 未找到，跳过")
        return False
    cmd = [exe, "-b", "-Q", str(quality), input_path, output_path]
    logger.info(f"🎨 posterize: {os.path.basename(input_path)} Q={quality}")
    try:
        _run_tracked(cmd)
        _strip_alpha_if_needed(input_path, output_path)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"posterize 失败: {e.stderr}")
        return False


def _strip_alpha_if_needed(src_path, out_path):
    """posterize 输出 RGBA，若输入为 RGB 则去掉多余 alpha 通道以减小体积"""
    try:
        src = Image.open(src_path)
        out = Image.open(out_path)
        if src.mode == "RGB" and out.mode in ("RGBA", "LA"):
            out.convert("RGB").save(out_path)
        src.close()
        out.close()
    except Exception as e:
        logger.warning(f"去除 alpha 通道失败: {e}")


def oxipng_optimize(input_path):
    """oxipng 无损优化（原地修改）"""
    exe = _tool_path("oxipng.exe")
    if not os.path.exists(exe):
        logger.warning("oxipng.exe 未找到，跳过")
        return
    cmd = [exe, "--opt", "6", "--strip", "all", input_path]
    logger.info(f"🔧 oxipng: {os.path.basename(input_path)}")
    try:
        _run_tracked(cmd)
    except subprocess.CalledProcessError as e:
        logger.error(f"oxipng 失败: {e.stderr}")


def convert_to_png(input_path, output_path):
    """JPG → PNG 转换"""
    img = Image.open(input_path)
    img.save(output_path, "PNG")
    logger.info(f"🖼 PNG转换: {os.path.basename(input_path)}")


def convert_to_jpeg(input_path, output_path, quality=80):
    """PNG → JPG 转换"""
    img = Image.open(input_path)
    if img.mode in ("RGBA", "P"):
        img = img.convert("RGB")
    img.save(output_path, "JPEG", quality=quality)
    logger.info(f"🖼 JPEG转换: {os.path.basename(input_path)} quality={quality}%")


def resize_by_long_edge(input_path, output_path, max_pixels):
    """按长边等比缩放"""
    img = Image.open(input_path)
    fmt = img.format or "PNG"
    w, h = img.size
    long_edge = max(w, h)
    if long_edge <= max_pixels:
        shutil.copy2(input_path, output_path)
        return False
    ratio = max_pixels / long_edge
    new_size = (int(w * ratio), int(h * ratio))
    img_resized = img.resize(new_size, Image.LANCZOS)

    # 显式指定格式保存（临时文件可能没有图片扩展名）
    if fmt == "JPEG":
        if img_resized.mode in ("RGBA", "LA", "P"):
            img_resized = img_resized.convert("RGB")
        img_resized.save(output_path, "JPEG", quality=95)
    else:
        img_resized.save(output_path, "PNG")

    logger.info(f"📐 缩放: {os.path.basename(input_path)} {w}x{h} → {new_size[0]}x{new_size[1]}")
    return True


def compress_png(input_path, output_path, quality_mode):
    """PNG 压缩主流程"""
    tmp = output_path + ".tmp.png"

    if quality_mode == "medium":
        # Posterizer → oxipng
        if posterize(input_path, tmp, quality=80):
            shutil.move(tmp, output_path)
        else:
            shutil.copy2(input_path, output_path)
        if os.path.exists(output_path):
            oxipng_optimize(output_path)
    elif quality_mode == "high":
        # 只 oxipng（TinyPNG 在主流程中处理）
        shutil.copy2(input_path, output_path)
        oxipng_optimize(output_path)
    else:
        shutil.copy2(input_path, output_path)

    if os.path.exists(tmp):
        os.remove(tmp)


def compress_jpg(input_path, output_path, quality_mode):
    """JPG 压缩"""
    quality_map = {"medium": 80, "high": 90, "none": 95}
    q = quality_map.get(quality_mode, 85)
    img = Image.open(input_path)
    if img.mode in ("RGBA", "P"):
        img = img.convert("RGB")
    img.save(output_path, "JPEG", quality=q, optimize=True)


# ============ TinyPNG ============

TINYPNG_URL = "https://api.tinify.com/shrink"


def tinypng_compress(input_path, output_path, api_key):
    """TinyPNG 云端压缩"""
    if not api_key:
        raise ValueError("未设置 API Key")

    with open(input_path, "rb") as f:
        response = requests.post(
            TINYPNG_URL,
            auth=("api", api_key),
            data=f.read(),
            timeout=30,
        )

    if response.status_code == 401:
        raise PermissionError("API Key 无效")
    if response.status_code == 429:
        raise RuntimeError("API 额度已用完")

    data = response.json()
    download_url = data["output"]["url"]

    compressed = requests.get(download_url, timeout=30).content
    with open(output_path, "wb") as f:
        f.write(compressed)

    orig = os.path.getsize(input_path)
    new_size = os.path.getsize(output_path)
    logger.info(f"☁️ TinyPNG: {os.path.basename(input_path)} {orig:,} → {new_size:,}")


def tinypng_validate(api_key):
    """验证 API Key"""
    import base64
    auth = base64.b64encode(f"api:{api_key}".encode()).decode()
    headers = {"Authorization": f"Basic {auth}"}
    # 发送一个 1x1 透明 PNG
    tiny_png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")
    r = requests.post(TINYPNG_URL, headers=headers, data=tiny_png, timeout=10)
    count = int(r.headers.get("Compression-Count", 0))
    return r.status_code == 201, count
