#!/usr/bin/env python3
"""轻图 Windows — Flet Material Design UI（接近 SwiftUI 风格）"""

import flet as ft
import flet_dropzone as ftd
import threading
import os
import json
import webbrowser
from pathlib import Path

from core import compressor, logger, gif_converter

CONFIG_FILE = Path.home() / "AppData" / "Local" / "LiteImage" / "config.json"
os.makedirs(CONFIG_FILE.parent, exist_ok=True)

DEFAULT_API_KEY = "NYPwQ8Kpjcng9gCSxmhy5hdzBGS7wpzC"
DEFAULT_BACKUP_KEY = "vbQQ2fGGLVLntTkpNRLCtQbPhFx4Jx8x"


def load_config():
    if CONFIG_FILE.exists():
        cfg = json.loads(CONFIG_FILE.read_text())
    else:
        cfg = {}
    cfg.setdefault("api_key", DEFAULT_API_KEY)
    cfg.setdefault("backup_api_key", DEFAULT_BACKUP_KEY)
    cfg.setdefault("debug_log", True)
    cfg.setdefault("overwrite", False)
    return cfg


def save_config(cfg):
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))


FMT_LABELS = {"none": "不转换", "jpg2png": "JPG → PNG", "png2jpg": "PNG → JPG"}
Q_LABELS = {"none": "不压缩", "medium": "中等质量", "high": "高质量"}
FMT_KEYS = {v: k for k, v in FMT_LABELS.items()}
Q_KEYS = {v: k for k, v in Q_LABELS.items()}


def _fmt_size(size):
    if size < 1024:
        return f"{size} B"
    elif size < 1024 * 1024:
        return f"{size / 1024:.1f} KB"
    else:
        return f"{size / (1024 * 1024):.1f} MB"


def _pad(h=0, v=0):
    """Flet 0.86 无 padding.symmetric，用 Padding 构造（h=水平, v=垂直）"""
    return ft.Padding(left=h, top=v, right=h, bottom=v)


class GIFConverterTab:
    """视频转 GIF / GIF 压缩 标签页"""

    def __init__(self, page: ft.Page):
        self.page = page
        self.files = []          # 文件列表：{path, kind: 'video'|'gif', info, status}
        self.running = False
        self._done_count = 0
        self.content = self._build()

    # ——— UI 构建 ———
    def _build(self):
        self.status_text = ft.Text("添加视频或 GIF", color=ft.Colors.GREY, size=12)

        add_btn = ft.Button(
            "＋ 添加文件", icon=ft.Icons.ADD,
            on_click=lambda e: self._pick_files()
        )
        clear_btn = ft.OutlinedButton("清空", on_click=lambda e: self._clear())
        self.start_btn = ft.FilledButton(
            "马上转换", icon=ft.Icons.PLAY_ARROW, on_click=lambda e: self._toggle()
        )

        top = ft.Row(
            [add_btn, self.status_text, ft.Container(expand=True), clear_btn, self.start_btn],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        )

        # 设置行
        self.quality_dd = ft.Dropdown(
            value="中等质量",
            options=[ft.dropdown.Option(v) for v in ["低质量", "中等质量", "高质量"]],
            width=140, text_size=12,
        )
        self.width_tf = ft.TextField(value="480", label="宽度(px)", width=90, height=44,
                                     keyboard_type=ft.KeyboardType.NUMBER, text_size=12)
        self.fps_tf = ft.TextField(value="25", label="帧率", width=80, height=44,
                                   keyboard_type=ft.KeyboardType.NUMBER, text_size=12)
        self.seconds_tf = ft.TextField(value="5", label="时长(秒)", width=80, height=44,
                                       keyboard_type=ft.KeyboardType.NUMBER, text_size=12)

        settings_row = ft.Row(
            [ft.Text("设置:", size=12, color=ft.Colors.GREY),
             self.quality_dd, self.width_tf, self.fps_tf, self.seconds_tf],
            spacing=8,
            alignment=ft.MainAxisAlignment.CENTER,
        )

        # 文件列表
        self.list_view = ft.ListView(spacing=8, expand=True)
        self._placeholder = ft.Container(
            ft.Column([
                ft.Icon(ft.Icons.MOVIE_OUTLINED, size=64, color=ft.Colors.GREY),
                ft.Text("添加视频（MP4/MOV/AVI）或 GIF 文件", size=14, color=ft.Colors.GREY),
            ], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            alignment=ft.Alignment.CENTER,
            expand=True
        )

        # 日志
        self.log_view = ft.ListView(spacing=2, height=120, auto_scroll=True)

        # 列表区域用 Dropzone 包装（支持拖放）
        list_area = ftd.Dropzone(
            content=ft.Column([
                self._placeholder,
                self.list_view,
            ], expand=True),
            allowed_file_types=["mp4", "mov", "avi", "mkv", "gif"],
            on_dropped=self._on_files_dropped,
            expand=True,
        )

        return ft.Column(
            [top, settings_row, list_area, self.log_view],
            expand=True, spacing=8,
        )

    # ——— 文件操作 ———
    def _pick_files(self):
        def _do():
            from tkinter import filedialog
            files = filedialog.askopenfilenames(
                title="选择视频或 GIF",
                filetypes=[("视频/GIF", "*.mp4 *.mov *.avi *.mkv *.gif")])
            if files:
                for f in files:
                    self._add_file(f)
                self._update_view()

        threading.Thread(target=_do, daemon=True).start()

    def _add_file(self, path):
        ext = Path(path).suffix.lower()
        kind = "gif" if ext == ".gif" else "video"
        info = {}
        if kind == "video":
            info = gif_converter.get_video_info(path)
        item = {"path": path, "kind": kind, "info": info, "status": "pending"}
        self.files.append(item)
        self._build_list_item(len(self.files) - 1, item)

    def _on_files_dropped(self, e):
        for file in e.files:
            path = file.path
            if not path:
                continue
            ext = os.path.splitext(path)[1].lower()
            if ext in (".mp4", ".mov", ".avi", ".mkv", ".gif"):
                self._add_file(path)
        self._update_view()

    def _build_list_item(self, idx, item):
        name = Path(item["path"]).name
        status_icon = ft.Icon(ft.Icons.CIRCLE_OUTLINED, size=18, color=ft.Colors.GREY)

        if item["kind"] == "video":
            info = item["info"]
            desc = f"视频  ·  {info.get('width', 0)}x{info.get('height', 0)}  ·  {info.get('duration', 0):.1f}s"
        else:
            desc = "GIF 压缩"

        del_btn = ft.IconButton(ft.Icons.CLOSE, icon_size=16, tooltip="移除",
                                on_click=lambda e, it=item: self._remove(it))

        card = ft.Card(
            ft.Container(
                ft.Row([
                    status_icon,
                    ft.Column([
                        ft.Text(name, size=12, weight=ft.FontWeight.W_500),
                        ft.Text(desc, size=11, color=ft.Colors.GREY),
                    ], spacing=2, expand=True),
                    del_btn,
                ], spacing=8),
                padding=_pad(12, 8),
            ),
        )
        item["_widgets"] = {"status": status_icon, "card": card}
        self.list_view.controls.append(card)

    def _remove(self, item):
        if item in self.files:
            idx = self.files.index(item)
            self.files.pop(idx)
            self.list_view.controls.pop(idx)
        self._update_view()

    def _clear(self):
        self.files.clear()
        self.list_view.controls.clear()
        self.log_view.controls.clear()
        self._update_view()

    def _update_view(self):
        n = len(self.files)
        self.status_text.value = f"✅ {self._done_count} 完成  |  共 {n} 个" if n else "添加视频或 GIF"
        self._placeholder.visible = (n == 0)
        self.list_view.visible = (n > 0)
        self.page.update()

    # ——— 转换 ———
    def _toggle(self):
        if self.running:
            self.running = False
            compressor.terminate()
            self.start_btn.text = "马上转换"
            self.start_btn.icon = ft.Icons.PLAY_ARROW
            self.start_btn.style = None
            self.page.update()
        else:
            self._start()

    def _start(self):
        if not self.files:
            return
        self.running = True
        self._done_count = 0
        self.start_btn.text = "■ 停止"
        self.start_btn.icon = ft.Icons.STOP
        self.start_btn.style = ft.ButtonStyle(bgcolor=ft.Colors.RED)
        self.page.update()

        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        quality_map = {"低质量": "low", "中等质量": "medium", "高质量": "high"}
        quality = quality_map.get(self.quality_dd.value, "medium")
        try:
            width = int(self.width_tf.value or 480)
            fps = int(self.fps_tf.value or 25)
            seconds = float(self.seconds_tf.value or 5)
        except ValueError:
            width, fps, seconds = 480, 25, 5.0
        # 参数下限/上限校验，避免非法值进入 ffmpeg/gifski 命令
        width = max(16, min(width, 3840))
        fps = max(1, min(fps, 60))
        seconds = max(0.1, min(seconds, 3600))

        for i, item in enumerate(self.files):
            if not self.running:
                break
            self._set_status(i, ft.Icons.HOURGLASS_EMPTY, ft.Colors.ORANGE)
            path = item["path"]
            base = str(Path(path).with_name(Path(path).stem))
            out_path = base + ".gif" if item["kind"] == "video" else base + "_compressed.gif"
            self._log(f"🔄 [{i+1}/{len(self.files)}] {Path(path).name}")
            try:
                if item["kind"] == "video":
                    gif_converter.convert_video_to_gif(
                        path, out_path, quality=quality, width=width, fps=fps, max_seconds=seconds)
                else:
                    gif_converter.compress_gif(
                        path, out_path, quality=quality, width=width, fps=fps)
                self._set_status(i, ft.Icons.CHECK_CIRCLE, ft.Colors.GREEN)
                self._done_count += 1
                self._log(f"✅ {Path(path).name} → {Path(out_path).name}")
            except Exception as e:
                self._set_status(i, ft.Icons.ERROR, ft.Colors.RED)
                self._log(f"❌ {Path(path).name}: {e}")
            self._update_view()

        self.running = False
        self.start_btn.text = "马上转换"
        self.start_btn.icon = ft.Icons.PLAY_ARROW
        self.start_btn.style = None
        self.page.update()

    def _set_status(self, idx, icon, color):
        if idx < len(self.files) and "_widgets" in self.files[idx]:
            w = self.files[idx]["_widgets"]["status"]
            w.name = icon
            w.color = color
            self.page.update()

    def _log(self, message):
        self.log_view.controls.append(ft.Text(message, size=11))
        self.page.update()


class LiteImageApp:
    def __init__(self, page: ft.Page):
        self.page = page
        self.cfg = load_config()
        self.items = []
        self.running = False
        self._done_count = 0
        self._total_saved = 0
        self._total_ratio = 0.0

        page.title = "轻图"
        page.window.width = 860
        page.window.height = 640
        page.window.min_width = 720
        page.window.min_height = 480
        page.theme_mode = ft.ThemeMode.SYSTEM
        page.padding = 16
        page.spacing = 12
        # 全局字体：思源黑体（Noto Sans SC）
        page.fonts = {"Noto Sans SC": "fonts/NotoSansSC.ttf"}
        page.theme = ft.Theme(font_family="Noto Sans SC")

        logger.enable(self.cfg.get("debug_log", True))
        self._build_ui()

    def _build_ui(self):
        self._selected_tab = 0

        # ——— Tab Bar（macOS 风格：图标 + 文字 + 选中高亮，右侧设置）———
        self._tab_image = self._make_tab_button("图片压缩", ft.Icons.PHOTO_LIBRARY_OUTLINED, 0)
        self._tab_gif = self._make_tab_button("视频转 GIF", ft.Icons.MOVIE_OUTLINED, 1)
        settings_btn = ft.IconButton(
            ft.Icons.SETTINGS_OUTLINED, tooltip="设置", on_click=lambda e: self._open_settings()
        )
        tab_bar = ft.Row(
            [self._tab_image, self._tab_gif, ft.Row([settings_btn])],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        )

        # ——— 内容区（if-else 切换）———
        self.gif_tab = GIFConverterTab(self.page)
        self._image_content = self._build_image_tab()
        self._content_area = ft.Container(content=self._image_content, expand=True)

        self.page.add(tab_bar, ft.Divider(height=1), self._content_area)
        self._update_view()

    def _make_tab_button(self, label, icon, index):
        return ft.Container(
            content=ft.Row([ft.Icon(icon, size=16), ft.Text(label, size=14)], spacing=6),
            padding=_pad(16, 8),
            border_radius=8,
            on_click=lambda e: self._switch_tab(index),
        )

    def _switch_tab(self, index):
        self._selected_tab = index
        # 更新两个按钮的选中样式
        for btn, selected in [(self._tab_image, index == 0), (self._tab_gif, index == 1)]:
            btn.bgcolor = ft.Colors.with_opacity(0.15, ft.Colors.BLUE) if selected else None
            btn.content.controls[0].color = ft.Colors.BLUE if selected else ft.Colors.GREY
            btn.content.controls[1].color = ft.Colors.BLUE if selected else ft.Colors.GREY
            btn.content.controls[1].weight = ft.FontWeight.W_600 if selected else ft.FontWeight.NORMAL
        self._content_area.content = self._image_content if index == 0 else self.gif_tab.content
        self.page.update()

    def _build_image_tab(self):
        # ——— 图片列表卡片 ———
        self.overwrite_switch = ft.Switch(
            label="覆盖原文件", value=self.cfg.get("overwrite", False),
            label_text_style=ft.TextStyle(size=12),
            scale=0.7,
        )
        self.status_text = ft.Text("", color=ft.Colors.GREY, size=12)
        self._item_count_text = ft.Text("0 张", color=ft.Colors.GREY, size=12)

        clear_btn = ft.TextButton(
            "清空", on_click=lambda e: self._clear(),
            style=ft.ButtonStyle(color=ft.Colors.RED),
        )

        list_header = ft.Row(
            [ft.Text("图片列表", size=14, weight=ft.FontWeight.W_600),
             self._item_count_text,
             self.overwrite_switch,
             ft.Row([clear_btn])],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        )

        self.list_view = ft.ListView(spacing=4, expand=True)
        self._placeholder = ft.Container(
            ft.Column([
                ft.Icon(ft.Icons.CLOUD_UPLOAD_OUTLINED, size=64, color=ft.Colors.GREY),
                ft.Text("点击「添加图片」选择图片文件", size=14, color=ft.Colors.GREY),
            ], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            alignment=ft.Alignment.CENTER,
            expand=True
        )

        list_card = ftd.Dropzone(
            content=ft.Container(
                ft.Column([
                    list_header,
                    ft.Divider(height=1),
                    self._placeholder,
                    self.list_view,
                ], spacing=8, expand=True),
                padding=12,
                bgcolor=ft.Colors.SURFACE_CONTAINER_LOW if hasattr(ft.Colors, "SURFACE_CONTAINER_LOW") else ft.Colors.GREY_50,
                border_radius=8,
                expand=True,
            ),
            allowed_file_types=["png", "jpg", "jpeg"],
            on_dropped=self._on_files_dropped,
            expand=True,
        )

        # ——— 压缩按钮（列表下方大按钮）———
        self.start_btn = ft.FilledButton(
            "马上压缩", icon=ft.Icons.PLAY_ARROW, on_click=lambda e: self._toggle(),
            expand=True,
        )
        self._compress_status = ft.Text("", size=12, color=ft.Colors.GREY)
        compress_row = ft.Row(
            [self.start_btn, self._compress_status],
            alignment=ft.MainAxisAlignment.CENTER,
            spacing=10,
        )

        # ——— 统计面板 ———
        self._stat_compressed = self._make_stat_box("0", "已压缩")
        self._stat_saved = self._make_stat_box("0 B", "节省空间")
        self._stat_ratio = self._make_stat_box("0%", "压缩率")
        self._stat_remaining = self._make_stat_box("—", "剩余额度")
        stats_row = ft.Row(
            [self._stat_compressed, self._stat_saved, self._stat_ratio, self._stat_remaining],
            spacing=12,
        )

        # ——— 日志 ———
        self.log_view = ft.ListView(spacing=2, height=120, auto_scroll=True)
        log_card = ft.Container(
            ft.Column([
                ft.Text("压缩日志", size=14, weight=ft.FontWeight.W_600),
                self.log_view,
            ], spacing=8),
            padding=12,
            bgcolor=ft.Colors.SURFACE_CONTAINER_LOW if hasattr(ft.Colors, "SURFACE_CONTAINER_LOW") else ft.Colors.GREY_50,
            border_radius=8,
        )

        hint = ft.Text("高质量：网络压缩（速度取决于网络），中质量：本地压缩（速度取决于电脑）", color=ft.Colors.GREY, size=11)

        return ft.Column(
            [list_card, compress_row, stats_row, log_card, hint],
            expand=True, spacing=12, scroll=ft.ScrollMode.AUTO,
        )

    def _make_stat_box(self, value, label):
        return ft.Container(
            ft.Column([
                ft.Text(value, size=20, weight=ft.FontWeight.BOLD),
                ft.Text(label, size=11, color=ft.Colors.GREY),
            ], spacing=4, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            padding=_pad(0, 12),
            bgcolor=ft.Colors.SURFACE_CONTAINER_LOW if hasattr(ft.Colors, "SURFACE_CONTAINER_LOW") else ft.Colors.GREY_50,
            border_radius=8,
            expand=True,
        )

    # ——— 文件操作 ———

    def _pick_files(self):
        def _do():
            from tkinter import filedialog
            files = filedialog.askopenfilenames(title="选择图片", filetypes=[("图片", "*.png *.jpg *.jpeg")])
            if files:
                for f in files:
                    self._add_file(f)
                self._update_view()

        import threading
        threading.Thread(target=_do, daemon=True).start()

    def _add_file(self, path):
        size = os.path.getsize(path)
        item = {"path": path, "format": "none", "quality": "high", "resize": 0, "_size": size}
        self.items.append(item)
        self._build_list_item(len(self.items) - 1, item)

    def _on_files_dropped(self, e):
        for file in e.files:
            path = file.path
            if not path:
                continue
            ext = os.path.splitext(path)[1].lower()
            if ext in (".png", ".jpg", ".jpeg"):
                self._add_file(path)
        self._update_view()

    def _build_list_item(self, idx, item):
        ext = Path(item["path"]).suffix.lower().lstrip(".")
        name = Path(item["path"]).name

        status_icon = ft.Icon(ft.Icons.CIRCLE_OUTLINED, size=16, color=ft.Colors.GREY)

        # 扩展名 badge（彩色）
        ext_color = (ft.Colors.BLUE if ext == "png"
                     else ft.Colors.ORANGE if ext in ("jpg", "jpeg")
                     else ft.Colors.GREY)
        ext_badge = ft.Container(
            ft.Text(ext.upper(), size=10, weight=ft.FontWeight.W_600, color=ext_color),
            padding=_pad(5, 1),
            bgcolor=ft.Colors.with_opacity(0.15, ext_color),
            border_radius=3,
        )

        # 缩放
        resize_tf = ft.TextField(
            value=str(item["resize"]) if item["resize"] else "",
            hint_text="px", width=72, height=32, text_size=11,
            keyboard_type=ft.KeyboardType.NUMBER,
            on_change=lambda e, it=item: self._on_resize_change(it, e),
        )
        resize_switch = ft.Switch(
            value=item["resize"] > 0, label="缩放",
            label_text_style=ft.TextStyle(size=11),
            scale=0.7,
            on_change=lambda e, it=item: self._on_resize_toggle(it, e, resize_tf),
        )

        # 缩放预设按钮
        preset_buttons = []
        for preset in [1920, 1280, 800]:
            preset_buttons.append(
                ft.TextButton(
                    f"{preset}",
                    style=ft.ButtonStyle(
                        text_style=ft.TextStyle(size=11),
                        padding=_pad(6, 0),
                    ),
                    on_click=lambda e, it=item, p=preset, tf=resize_tf: self._on_resize_preset(it, p, tf),
                )
            )

        # 格式 / 质量
        # 根据文件格式过滤转换选项：JPG 只显示「JPG → PNG」，PNG 只显示「PNG → JPG」
        if ext in ("jpg", "jpeg"):
            available_fmts = ["none", "jpg2png"]
        else:
            available_fmts = ["none", "png2jpg"]
        fmt_dd = ft.Dropdown(
            value=FMT_LABELS[item["format"]],
            options=[ft.dropdown.Option(FMT_LABELS[f]) for f in available_fmts],
            width=110, text_size=10, dense=True,
            on_select=lambda e, it=item: self._on_fmt_change(it, e),
        )
        q_dd = ft.Dropdown(
            value=Q_LABELS[item["quality"]],
            options=[ft.dropdown.Option(v) for v in Q_LABELS.values()],
            width=90, text_size=10, dense=True,
            on_select=lambda e, it=item: self._on_q_change(it, e),
        )

        del_btn = ft.IconButton(
            ft.Icons.CLOSE, icon_size=14, tooltip="移除",
            on_click=lambda e, it=item: self._remove(it),
        )

        # 第一行：文件名 + badge + 大小
        row1 = ft.Row([
            ft.Text(name, size=12, weight=ft.FontWeight.W_500),
            ext_badge,
            ft.Text(_fmt_size(item["_size"]), size=11, color=ft.Colors.GREY),
        ], spacing=6)

        # 第二行：缩放 + 预设 + 格式 + 质量 + 删除
        row2 = ft.Row([
            resize_switch, resize_tf, *preset_buttons,
            ft.Container(expand=True),
            fmt_dd, q_dd, del_btn,
        ], spacing=4)

        # 外层：状态图标垂直居中于两行内容
        card = ft.Container(
            ft.Row([
                status_icon,
                ft.Column([row1, row2], spacing=4, expand=True),
            ], spacing=8, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            padding=_pad(8, 6),
            bgcolor=ft.Colors.SURFACE_CONTAINER_LOW if hasattr(ft.Colors, "SURFACE_CONTAINER_LOW") else ft.Colors.GREY_50,
            border_radius=4,
        )

        item["_widgets"] = {
            "status": status_icon, "resize_switch": resize_switch,
            "resize_tf": resize_tf, "fmt": fmt_dd, "q": q_dd, "card": card,
        }
        self.list_view.controls.append(card)

    def _remove(self, item):
        if item in self.items:
            idx = self.items.index(item)
            self.items.pop(idx)
            self.list_view.controls.pop(idx)
        self._update_view()

    def _clear(self):
        self.items.clear()
        self.list_view.controls.clear()
        self._update_view()

    def _on_fmt_change(self, item, e):
        item["format"] = FMT_KEYS.get(e.control.value, "none")

    def _on_q_change(self, item, e):
        item["quality"] = Q_KEYS.get(e.control.value, "high")

    def _on_resize_toggle(self, item, e, tf):
        if e.control.value:
            tf.visible = True
            item["resize"] = int(tf.value or 2048)
            tf.value = str(item["resize"])
        else:
            tf.visible = False
            item["resize"] = 0
        self.page.update()

    def _on_resize_change(self, item, e):
        val = e.control.value
        if val.isdigit() and 100 <= int(val) <= 8000:
            item["resize"] = int(val)

    def _on_resize_preset(self, item, preset, tf):
        item["resize"] = preset
        tf.value = str(preset)
        tf.visible = True
        item["_widgets"]["resize_switch"].value = True
        self.page.update()

    def _update_view(self):
        n = len(self.items)
        self._item_count_text.value = f"{n} 张"
        self._placeholder.visible = (n == 0)
        self.list_view.visible = (n > 0)
        # 统计面板
        self._stat_compressed.content.controls[0].value = str(self._done_count)
        self._stat_saved.content.controls[0].value = _fmt_size(self._total_saved)
        avg = self._total_ratio / self._done_count if self._done_count else 0
        self._stat_ratio.content.controls[0].value = f"{avg:.1f}%"
        self.page.update()

    # ——— 压缩 ———

    def _toggle(self):
        if self.running:
            self.running = False
            compressor.terminate()
            self.start_btn.text = "马上压缩"
            self.start_btn.icon = ft.Icons.PLAY_ARROW
            self.start_btn.style = None
            self._compress_status.value = ""
            self.page.update()
        else:
            self._start_compression()

    def _start_compression(self):
        if not self.items:
            return
        self.running = True
        self._done_count = 0
        self._total_saved = 0
        self._total_ratio = 0.0
        self.log_view.controls.clear()
        self.start_btn.text = "■ 停止"
        self.start_btn.icon = ft.Icons.STOP
        self.start_btn.style = ft.ButtonStyle(bgcolor=ft.Colors.RED)
        self._compress_status.value = "压缩中..."
        self.cfg["overwrite"] = self.overwrite_switch.value
        save_config(self.cfg)
        self.page.update()

        thread = threading.Thread(target=self._run_compression, daemon=True)
        thread.start()

    def _run_compression(self):
        overwrite = self.overwrite_switch.value
        api_key = self.cfg.get("api_key", "")
        backup_key = self.cfg.get("backup_api_key", "")

        while self.items and self.running:
            item = self.items[0]
            input_path = item["path"]
            fmt = item["format"]
            quality = item["quality"]
            resize_px = item["resize"]
            ext = Path(input_path).suffix.lower()

            try:
                out_ext = {"jpg2png": ".png", "png2jpg": ".jpg"}.get(fmt, ext)
                tmp = input_path + ".liteimage" + out_ext

                if overwrite:
                    if out_ext != ext:
                        # 覆盖 + 格式转换：输出到同名新扩展名，稍后删除原文件
                        out_path = str(Path(input_path).with_name(Path(input_path).stem + out_ext))
                    else:
                        out_path = input_path
                else:
                    out_path = str(Path(input_path).with_name(Path(input_path).stem + "-compressed" + out_ext))

                work_file = input_path
                if resize_px > 0:
                    tmp_r = input_path + ".resize.tmp"
                    compressor.resize_by_long_edge(input_path, tmp_r, resize_px)
                    work_file = tmp_r

                if fmt == "png2jpg":
                    if quality == "high" and ext == ".png" and api_key:
                        # TinyPNG 压缩 → 转 JPG
                        tpng = tmp + ".tinypng.png"
                        try:
                            compressor.tinypng_compress(work_file, tpng, api_key)
                        except Exception:
                            try:
                                compressor.tinypng_compress(work_file, tpng, backup_key)
                            except Exception:
                                tpng = None
                        src_for_jpg = tpng if tpng and os.path.exists(tpng) else work_file
                        compressor.convert_to_jpeg(src_for_jpg, tmp, quality=90)
                        if tpng and os.path.exists(tpng):
                            os.remove(tpng)
                    else:
                        compressor.convert_to_jpeg(work_file, tmp, quality={"medium": 80, "high": 90, "none": 95}[quality])
                elif quality == "high" and ext == ".png" and fmt == "none" and api_key:
                    try:
                        compressor.tinypng_compress(work_file, tmp, api_key)
                    except Exception:
                        try:
                            compressor.tinypng_compress(work_file, tmp, backup_key)
                        except Exception:
                            compressor.compress_png(work_file, tmp, "high")
                elif fmt == "jpg2png":
                    compressor.convert_to_png(work_file, tmp)
                    if quality != "none":
                        t2 = tmp + ".poster.png"
                        if compressor.posterize(tmp, t2, quality=80):
                            os.replace(t2, tmp)
                        compressor.oxipng_optimize(tmp)
                elif ext == ".png" and fmt == "none":
                    compressor.compress_png(work_file, tmp, quality)
                else:
                    compressor.compress_jpg(work_file, tmp, quality)

                # 停止检查：用户在压缩过程中点了停止，则不移动结果、不删除原文件
                if not self.running:
                    break

                if os.path.exists(tmp):
                    os.replace(tmp, out_path)
                # 覆盖 + 格式转换：删除原文件（如 photo.png → photo.jpg）
                if overwrite and out_ext != ext and input_path != out_path and os.path.exists(input_path):
                    os.remove(input_path)
                for f in [work_file if work_file != input_path else None]:
                    if f and os.path.exists(f) and f != out_path:
                        os.remove(f)

                self._done_count += 1
                # 统计 + 日志
                if os.path.exists(out_path):
                    new_size = os.path.getsize(out_path)
                    orig_size = item["_size"]
                    saved = orig_size - new_size
                    ratio = (saved / orig_size * 100) if orig_size else 0
                    self._total_saved += max(0, saved)
                    self._total_ratio += ratio
                    self._log(f"✅ {Path(input_path).name}: {_fmt_size(orig_size)} → {_fmt_size(new_size)}  节省 {ratio:.1f}%")

            except Exception as e:
                self._log(f"❌ {Path(input_path).name}: {e}")
                logger.logger.error(f"❌ {Path(input_path).name}: {e}")

            # 压缩完毕（成功或失败），自动移除该项
            self.items.pop(0)
            self.list_view.controls.pop(0)
            self._update_view()

        self.running = False
        self.start_btn.text = "马上压缩"
        self.start_btn.icon = ft.Icons.PLAY_ARROW
        self.start_btn.style = None
        self._compress_status.value = f"完成 {self._done_count} 张"
        self.page.update()

    def _set_status(self, idx, icon, color):
        if idx < len(self.items) and "_widgets" in self.items[idx]:
            w = self.items[idx]["_widgets"]["status"]
            w.name = icon
            w.color = color
            self.page.update()

    def _log(self, message):
        self.log_view.controls.append(ft.Text(message, size=11))
        self.page.update()

    # ——— 设置 ———

    def _open_settings(self):
        api_key = self.cfg.get("api_key", "")
        backup_key = self.cfg.get("backup_api_key", "")
        debug_val = self.cfg.get("debug_log", True)

        api_tf = ft.TextField(value=api_key, label="主 API Key", password=True, can_reveal_password=False)
        backup_tf = ft.TextField(value=backup_key, label="备用 API Key", password=True, can_reveal_password=False)
        debug_sw = ft.Switch(value=debug_val, label="启用 Debug 日志")
        status_txt = ft.Text("", size=12)

        def test_key(key, prefix):
            try:
                valid, count = compressor.tinypng_validate(key)
                status_txt.value = f"{prefix} ✅ 有效，本月已用 {count} 次" if valid else f"{prefix} ❌ 无效"
                status_txt.color = ft.Colors.GREEN if valid else ft.Colors.RED
                self.page.update()
            except Exception as e:
                status_txt.value = f"{prefix} ❌ {e}"
                status_txt.color = ft.Colors.RED
                self.page.update()

        def save(e):
            self.cfg["api_key"] = api_tf.value
            self.cfg["backup_api_key"] = backup_tf.value
            self.cfg["debug_log"] = debug_sw.value
            save_config(self.cfg)
            logger.enable(debug_sw.value)
            self.page.pop_dialog()

        def restore(e):
            api_tf.value = DEFAULT_API_KEY
            backup_tf.value = DEFAULT_BACKUP_KEY
            self.page.update()

        dlg = ft.AlertDialog(
            title=ft.Text("设置"),
            content=ft.Column([
                ft.Text("API Key", size=14, weight=ft.FontWeight.W_500),
                api_tf,
                ft.Row([
                    ft.TextButton("测试主 Key", on_click=lambda e: test_key(api_tf.value, "主Key")),
                    ft.TextButton("测试备用", on_click=lambda e: test_key(backup_tf.value, "备用Key")),
                ]),
                backup_tf,
                ft.Row([
                    ft.TextButton("🔄 还原默认 Key", on_click=restore),
                    ft.TextButton("🔗 申请免费 Key", on_click=lambda e: webbrowser.open("https://tinypng.com/developers")),
                ]),
                status_txt,
                ft.Divider(),
                ft.Text("Debug", size=14, weight=ft.FontWeight.W_500),
                debug_sw,
                ft.Row([
                    ft.TextButton("📂 打开日志目录", on_click=lambda e: os.startfile(logger.get_log_dir()) if os.name == "nt" else None),
                    ft.TextButton("📄 查看日志", on_click=lambda e: os.startfile(logger.get_log_path()) if os.path.exists(logger.get_log_path()) else None),
                ]),
            ], spacing=8, width=420, scroll=ft.ScrollMode.AUTO),
            actions=[ft.FilledButton("💾 保存设置", on_click=save)],
        )
        self.page.show_dialog(dlg)


def main(page: ft.Page):
    LiteImageApp(page)


if __name__ == "__main__":
    ft.run(main)
