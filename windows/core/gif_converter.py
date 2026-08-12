"""视频转 GIF — ffmpeg 提取帧 + gifski 合成 + GIF 压缩

复用 compressor 的进程跟踪机制（compressor.terminate() 可中断）。
注意：gifski 1.7.1 只接受 PNG 帧序列输入（视频/GIF 解码需先经 ffmpeg）。
"""

import subprocess
import os
import sys
import re
import tempfile
import shutil
import logging

logger = logging.getLogger("LiteImage")


def _resource_dir():
    """资源目录（tools/ 的父目录），兼容 PyInstaller 打包"""
    if getattr(sys, "frozen", False):
        return sys._MEIPASS
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


TOOLS_DIR = os.path.join(_resource_dir(), "tools")

# gifski 质量预设
QUALITY_PRESETS = {
    "low": {"quality": 50, "label": "低质量"},
    "medium": {"quality": 70, "label": "中等质量"},
    "high": {"quality": 90, "label": "高质量"},
}


def _tool_path(name):
    return os.path.join(TOOLS_DIR, name)


def _tool(name):
    """返回可用的工具路径（优先 tools/，回退系统 PATH）"""
    exe = _tool_path(name)
    if os.path.exists(exe):
        return exe
    found = shutil.which(os.path.splitext(name)[0])
    return found or exe


def get_video_info(path):
    """用 ffmpeg 读取视频信息，返回 dict(duration, width, height, fps)"""
    ffmpeg = _tool("ffmpeg.exe")
    cmd = [ffmpeg, "-i", path]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        _, stderr = proc.communicate()
    except Exception as e:
        logger.warning(f"读取视频信息失败: {e}")
        return {"duration": 5.0, "width": 480, "height": 270, "fps": 25}

    info = {"duration": 5.0, "width": 480, "height": 270, "fps": 25}

    # Duration: 00:00:12.34
    m = re.search(r"Duration:\s*(\d+):(\d+):(\d+\.?\d*)", stderr)
    if m:
        h, mi, s = int(m.group(1)), int(m.group(2)), float(m.group(3))
        info["duration"] = h * 3600 + mi * 60 + s

    # 1280x720
    m = re.search(r"(\d{2,5})x(\d{2,5})", stderr)
    if m:
        info["width"] = int(m.group(1))
        info["height"] = int(m.group(2))

    # 30 fps / 29.97 fps
    m = re.search(r"(\d+\.?\d*)\s*fps", stderr)
    if m:
        info["fps"] = float(m.group(1))

    return info


def _extract_frames(compressor, input_path, frames_dir, width, fps, max_seconds=None):
    """ffmpeg 提取帧到 frames_dir，返回是否成功"""
    ffmpeg = _tool("ffmpeg.exe")
    frame_pattern = os.path.join(frames_dir, "frame_%04d.png")
    cmd = [ffmpeg, "-y"]
    if max_seconds is not None:
        cmd += ["-t", f"{max_seconds:.2f}"]
    cmd += [
        "-i", input_path,
        "-vf", f"scale={width}:-1:flags=lanczos,fps={fps}",
        "-q:v", "1",
        frame_pattern,
    ]
    logger.info(f"🎬 ffmpeg 提帧: {os.path.basename(input_path)} width={width} fps={fps}")
    compressor._run_tracked(cmd)


def _frames_to_gif(compressor, frames_dir, output_path, quality, width, fps):
    """gifski 用 PNG 帧序列合成 GIF"""
    gifski = _tool("gifski.exe")
    q = QUALITY_PRESETS.get(quality, QUALITY_PRESETS["medium"])["quality"]
    frame_files = sorted(
        os.path.join(frames_dir, f) for f in os.listdir(frames_dir)
        if f.lower().endswith(".png")
    )
    if not frame_files:
        raise RuntimeError("未提取到帧，无法合成 GIF")

    cmd = [gifski, "-Q", str(q), "-W", str(width), "-r", str(fps), "-o", output_path] + frame_files
    logger.info(f"🎨 gifski 合成: {os.path.basename(output_path)} Q={q}")
    compressor._run_tracked(cmd)


def _extract_gif_frames_pil(input_path, frames_dir, width):
    """用 PIL 提取 GIF 帧（替代 ffmpeg 的 gif demuxer，精简版 ffmpeg 无此 demuxer）"""
    from PIL import Image
    img = Image.open(input_path)
    n = getattr(img, "n_frames", 1)
    for i in range(n):
        img.seek(i)
        frame = img.convert("RGBA")
        if frame.width > width:
            h = max(1, int(frame.height * width / frame.width))
            frame = frame.resize((width, h), Image.LANCZOS)
        frame.convert("RGB").save(os.path.join(frames_dir, f"frame_{i:04d}.png"))
    logger.info(f"🎞 PIL 提帧: {os.path.basename(input_path)} {n} 帧")


def convert_video_to_gif(video_path, output_path, quality="medium", width=480, fps=25, max_seconds=5.0):
    """视频 → GIF：ffmpeg 提取帧，gifski 合成。返回输出路径，失败抛异常"""
    from core import compressor

    tmp_dir = tempfile.mkdtemp(prefix="gif_conv_")
    frames_dir = os.path.join(tmp_dir, "frames")
    os.makedirs(frames_dir, exist_ok=True)
    try:
        _extract_frames(compressor, video_path, frames_dir, width, fps, max_seconds=max_seconds)
        _frames_to_gif(compressor, frames_dir, output_path, quality, width, fps)
        return output_path
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def compress_gif(input_path, output_path, quality="medium", width=480, fps=25):
    """GIF 压缩：PIL 提取帧 → gifski 重编码。返回输出路径，失败抛异常"""
    from core import compressor

    tmp_dir = tempfile.mkdtemp(prefix="gif_comp_")
    frames_dir = os.path.join(tmp_dir, "frames")
    os.makedirs(frames_dir, exist_ok=True)
    try:
        _extract_gif_frames_pil(input_path, frames_dir, width)
        _frames_to_gif(compressor, frames_dir, output_path, quality, width, fps)
        return output_path
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
