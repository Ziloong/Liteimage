#!/usr/bin/env python3
"""轻图 Windows — Flet Material Design UI（接近 SwiftUI 风格）"""

import flet as ft
import threading
import os
import json
import webbrowser
from pathlib import Path

from core import compressor, logger

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
    cfg.setdefault("debug_log", False)
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


class LiteImageApp:
    def __init__(self, page: ft.Page):
        self.page = page
        self.cfg = load_config()
        self.items = []
        self.running = False
        self._done_count = 0

        page.title = "轻图"
        page.window.width = 860
        page.window.height = 640
        page.window.min_width = 720
        page.window.min_height = 480
        page.theme_mode = ft.ThemeMode.SYSTEM
        page.padding = 16
        page.spacing = 12

        logger.enable(self.cfg.get("debug_log", False))
        self._build_ui()

    def _build_ui(self):
        # ——— 顶栏 ———
        self.status_text = ft.Text("拖放或点击添加图片", color=ft.Colors.GREY, size=13)

        add_btn = ft.ElevatedButton(
            "＋ 添加图片", icon=ft.Icons.ADD_PHOTO_ALTERNATE_OUTLINED,
            on_click=lambda e: self._pick_files()
        )
        clear_btn = ft.OutlinedButton("清空", on_click=lambda e: self._clear())
        settings_btn = ft.IconButton(
            ft.Icons.SETTINGS_OUTLINED, tooltip="设置", on_click=lambda e: self._open_settings()
        )
        self.start_btn = ft.FilledButton(
            "马上压缩", icon=ft.Icons.PLAY_ARROW, on_click=lambda e: self._toggle()
        )

        top = ft.Row(
            [add_btn, clear_btn, self.status_text, ft.Row([self.start_btn, settings_btn])],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        )

        # ——— 列表 ———
        self.list_view = ft.ListView(spacing=8, expand=True)
        self._placeholder = ft.Container(
            ft.Column([
                ft.Icon(ft.Icons.CLOUD_UPLOAD_OUTLINED, size=64, color=ft.Colors.GREY),
                ft.Text("拖放图片到此处，或点击「添加图片」", size=16, color=ft.Colors.GREY),
            ], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            expand=True
        )

        # ——— 底部 ———
        self.overwrite_switch = ft.Switch(
            label="覆盖原文件", value=self.cfg.get("overwrite", False),
        )
        hint = ft.Text("中质量：本地压缩  |  高质量：网络压缩", color=ft.Colors.GREY, size=11)

        bottom = ft.Row(
            [self.overwrite_switch, hint],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        )

        page = self.page
        page.add(top, self._placeholder, self.list_view, bottom)
        self._update_view()

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

    def _build_list_item(self, idx, item):
        ext = Path(item["path"]).suffix.upper().replace(".", "")
        name = Path(item["path"]).name

        status_icon = ft.Icon(ft.Icons.CIRCLE_OUTLINED, size=18, color=ft.Colors.GREY)

        # 缩放
        resize_tf = ft.TextField(
            value=str(item["resize"]) if item["resize"] else "",
            hint_text="px", width=68, height=36, text_size=12,
            keyboard_type=ft.KeyboardType.NUMBER,
            on_change=lambda e: self._on_resize_change(idx, e),
        )
        resize_switch = ft.Switch(
            value=item["resize"] > 0, label="缩放",
            on_change=lambda e: self._on_resize_toggle(idx, e, resize_tf),
        )

        # 格式
        fmt_dd = ft.Dropdown(
            value=FMT_LABELS[item["format"]],
            options=[ft.dropdown.Option(v) for v in FMT_LABELS.values()],
            width=120, text_size=12,
            on_change=lambda e: self._on_fmt_change(idx, e),
        )

        # 质量
        q_dd = ft.Dropdown(
            value=Q_LABELS[item["quality"]],
            options=[ft.dropdown.Option(v) for v in Q_LABELS.values()],
            width=100, text_size=12,
            on_change=lambda e: self._on_q_change(idx, e),
        )

        # 删除
        del_btn = ft.IconButton(
            ft.Icons.CLOSE, icon_size=16, tooltip="移除",
            on_click=lambda e: self._remove(idx),
        )

        card = ft.Card(
            ft.Container(
                ft.Row([
                    status_icon,
                    ft.Column([
                        ft.Text(name, size=13, weight=ft.FontWeight.W_500),
                        ft.Text(f"{ext}  ·  {_fmt_size(item['_size'])}", size=11, color=ft.Colors.GREY),
                    ], spacing=2, expand=True),
                    resize_switch, resize_tf,
                    fmt_dd, q_dd, del_btn,
                ], spacing=8),
                padding=ft.padding.symmetric(horizontal=12, vertical=8),
            ),
        )

        item["_widgets"] = {
            "status": status_icon, "resize_switch": resize_switch,
            "resize_tf": resize_tf, "fmt": fmt_dd, "q": q_dd, "card": card,
        }
        self.list_view.controls.append(card)

    def _remove(self, idx):
        self.items.pop(idx)
        self.list_view.controls.pop(idx)
        self._update_view()

    def _clear(self):
        self.items.clear()
        self.list_view.controls.clear()
        self._update_view()

    def _on_fmt_change(self, idx, e):
        self.items[idx]["format"] = FMT_KEYS.get(e.control.value, "none")

    def _on_q_change(self, idx, e):
        self.items[idx]["quality"] = Q_KEYS.get(e.control.value, "high")

    def _on_resize_toggle(self, idx, e, tf):
        if e.control.value:
            tf.visible = True
            self.items[idx]["resize"] = int(tf.value or 2048)
            tf.value = str(self.items[idx]["resize"])
        else:
            tf.visible = False
            self.items[idx]["resize"] = 0
        self.page.update()

    def _on_resize_change(self, idx, e):
        val = e.control.value
        if val.isdigit() and 100 <= int(val) <= 8000:
            self.items[idx]["resize"] = int(val)

    def _update_view(self):
        n = len(self.items)
        self.status_text.value = f"✅ {self._done_count} 完成  |  共 {n} 张" if n else "拖放或点击添加图片"
        self._placeholder.visible = (n == 0)
        self.list_view.visible = (n > 0)
        self.page.update()

    # ——— 压缩 ———

    def _toggle(self):
        if self.running:
            self.running = False
            self.start_btn.text = "马上压缩"
            self.start_btn.icon = ft.Icons.PLAY_ARROW
            self.start_btn.style = None
            self.page.update()
        else:
            self._start_compression()

    def _start_compression(self):
        if not self.items:
            return
        self.running = True
        self._done_count = 0
        self.start_btn.text = "■ 停止"
        self.start_btn.icon = ft.Icons.STOP
        self.start_btn.style = ft.ButtonStyle(bgcolor=ft.Colors.RED)
        self.cfg["overwrite"] = self.overwrite_switch.value
        save_config(self.cfg)
        self.page.update()

        thread = threading.Thread(target=self._run_compression, daemon=True)
        thread.start()

    def _run_compression(self):
        overwrite = self.overwrite_switch.value
        api_key = self.cfg.get("api_key", "")
        backup_key = self.cfg.get("backup_api_key", "")

        for i, item in enumerate(self.items):
            if not self.running:
                break

            self._set_status(i, ft.Icons.HOURGLASS_EMPTY, ft.Colors.ORANGE)
            input_path = item["path"]
            fmt = item["format"]
            quality = item["quality"]
            resize_px = item["resize"]
            ext = Path(input_path).suffix.lower()

            try:
                tmp = input_path + ".liteimage.tmp"
                out_ext = {"jpg2png": ".png", "png2jpg": ".jpg"}.get(fmt, ext)
                out_path = input_path if overwrite else str(
                    Path(input_path).with_name(Path(input_path).stem + "-compressed" + out_ext))

                work_file = input_path
                if resize_px > 0:
                    tmp_r = input_path + ".resize.tmp"
                    compressor.resize_by_long_edge(input_path, tmp_r, resize_px)
                    work_file = tmp_r

                if fmt == "png2jpg":
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
                    t2 = tmp + ".png"
                    compressor.convert_to_png(work_file, t2)
                    compressor.posterize(t2, tmp, quality=80)
                    compressor.oxipng_optimize(tmp)
                elif ext == ".png" and fmt == "none":
                    compressor.compress_png(work_file, tmp, quality)
                else:
                    compressor.compress_jpg(work_file, tmp, quality)

                if os.path.exists(out_path) and overwrite:
                    os.remove(out_path)
                if os.path.exists(tmp):
                    os.replace(tmp, out_path)
                for f in [work_file if work_file != input_path else None]:
                    if f and os.path.exists(f) and f != out_path:
                        os.remove(f)

                self._set_status(i, ft.Icons.CHECK_CIRCLE, ft.Colors.GREEN)
                self._done_count += 1
                self._update_status_text()

            except Exception as e:
                self._set_status(i, ft.Icons.ERROR, ft.Colors.RED)
                logger.logger.error(f"❌ {Path(input_path).name}: {e}")

        self.running = False
        self.start_btn.text = "马上压缩"
        self.start_btn.icon = ft.Icons.PLAY_ARROW
        self.start_btn.style = None
        self.page.update()

    def _set_status(self, idx, icon, color):
        if idx < len(self.items) and "_widgets" in self.items[idx]:
            w = self.items[idx]["_widgets"]["status"]
            w.name = icon
            w.color = color
            self.page.update()

    def _update_status_text(self):
        self.status_text.value = f"✅ {self._done_count} 完成  |  共 {len(self.items)} 张"
        self.page.update()

    # ——— 设置 ———

    def _open_settings(self):
        api_key = self.cfg.get("api_key", "")
        backup_key = self.cfg.get("backup_api_key", "")
        debug_val = self.cfg.get("debug_log", False)

        api_tf = ft.TextField(value=api_key, label="主 API Key", password=True, can_reveal_password=True)
        backup_tf = ft.TextField(value=backup_key, label="备用 API Key", password=True, can_reveal_password=True)
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
            dlg.open = False
            self.page.update()

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
        self.page.open(dlg)


def main(page: ft.Page):
    LiteImageApp(page)


if __name__ == "__main__":
    ft.app(target=main)
