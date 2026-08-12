#!/usr/bin/env python3
"""轻图 Windows — CustomTkinter 现代 UI"""

import customtkinter as ctk
from tkinter import filedialog, messagebox
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

ctk.set_appearance_mode("System")
ctk.set_default_color_theme("blue")


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


class ImageRow(ctk.CTkFrame):
    """单行图片条目"""

    def __init__(self, master, item, on_remove, on_change, **kw):
        super().__init__(master, fg_color=("gray90", "gray17"), corner_radius=6, **kw)
        self.item = item
        self.on_remove = on_remove
        self.on_change = on_change

        # 状态
        self.status_label = ctk.CTkLabel(self, text="⏳", width=30, font=("", 14))
        self.status_label.pack(side="left", padx=(8, 2))

        # 文件信息
        info = ctk.CTkFrame(self, fg_color="transparent")
        info.pack(side="left", fill="x", expand=True, padx=4)
        name = Path(item["path"]).name
        ext = Path(item["path"]).suffix.upper().replace(".", "")
        ctk.CTkLabel(info, text=f"{name}  ", font=("", 11, "bold")).pack(anchor="w")
        size_label = ctk.CTkLabel(info, text=self._fmt_size(item.get("_size", 0)),
                                  font=("", 10), text_color="gray")
        size_label.pack(anchor="w")

        # 右侧控制
        ctrl = ctk.CTkFrame(self, fg_color="transparent")
        ctrl.pack(side="right", padx=4)

        # 缩放
        resize_var = ctk.IntVar(value=item.get("resize", 0))
        self._resize_var = resize_var

        def toggle_resize():
            if resize_var.get() == 0:
                dlg = ctk.CTkInputDialog(text="长边像素 (100-8000):", title="缩放设置")
                val = dlg.get_input()
                if val and val.isdigit():
                    v = int(val)
                    if 100 <= v <= 8000:
                        resize_var.set(v)
                        item["resize"] = v
                        self._update_resize_btn()
                        on_change()

        self._resize_btn = ctk.CTkButton(ctrl, text="↔", width=28, height=24,
                                          font=("", 11), command=toggle_resize,
                                          fg_color="transparent" if resize_var.get() == 0 else None)
        self._resize_btn.pack(side="left", padx=1)
        if resize_var.get() > 0:
            ctk.CTkLabel(ctrl, text=f"{resize_var.get()}px", font=("", 9)).pack(side="left", padx=1)

        # 格式
        fmt_var = ctk.StringVar(value=item.get("format", "none"))
        fmt_menu = ctk.CTkOptionMenu(ctrl, values=["不转换", "JPG→PNG", "PNG→JPG"],
                                      variable=fmt_var, width=100, height=24, font=("", 11),
                                      command=lambda v: self._on_fmt_change(v))
        fmt_menu.pack(side="left", padx=2)

        # 质量
        q_var = ctk.StringVar(value=item.get("quality", "high"))
        q_menu = ctk.CTkOptionMenu(ctrl, values=["不压缩", "中等质量", "高质量"],
                                    variable=q_var, width=90, height=24, font=("", 11),
                                    command=lambda v: self._on_quality_change(v))
        q_menu.pack(side="left", padx=2)

        # 删除
        ctk.CTkButton(ctrl, text="✕", width=24, height=24, fg_color="transparent",
                       hover_color="red", font=("", 12), command=on_remove).pack(side="left", padx=1)

    def _on_fmt_change(self, v):
        m = {"不转换": "none", "JPG→PNG": "jpg2png", "PNG→JPG": "png2jpg"}
        self.item["format"] = m.get(v, "none")
        self.on_change()

    def _on_quality_change(self, v):
        m = {"不压缩": "none", "中等质量": "medium", "高质量": "high"}
        self.item["quality"] = m.get(v, "high")
        self.on_change()

    def _update_resize_btn(self):
        v = self._resize_var.get()
        self._resize_btn.configure(fg_color=None if v > 0 else "transparent")

    @staticmethod
    def _fmt_size(size):
        if size < 1024:
            return f"{size} B"
        elif size < 1024 * 1024:
            return f"{size / 1024:.1f} KB"
        else:
            return f"{size / (1024 * 1024):.1f} MB"


class LiteImageApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("轻图")
        self.geometry("860x640")
        self.minsize(720, 480)
        self.cfg = load_config()
        self.items = []
        self.row_widgets = []
        self.running = False
        self._build_ui()
        logger.enable(self.cfg.get("debug_log", False))

    def _build_ui(self):
        # 顶栏
        top = ctk.CTkFrame(self, fg_color="transparent")
        top.pack(fill="x", padx=12, pady=(12, 4))

        ctk.CTkButton(top, text="＋ 添加图片", width=100, command=self.add_files).pack(side="left", padx=2)
        ctk.CTkButton(top, text="清空", width=70, fg_color="transparent",
                       border_width=1, command=self.clear_list).pack(side="left", padx=2)

        self.btn_start = ctk.CTkButton(top, text="▶ 马上压缩", width=120, command=self.start_compression)
        self.btn_start.pack(side="right", padx=2)
        ctk.CTkButton(top, text="⚙", width=36, fg_color="transparent",
                       command=self.open_settings).pack(side="right", padx=2)

        # 统计
        self.status_label = ctk.CTkLabel(top, text="拖放或点击添加图片", text_color="gray")
        self.status_label.pack(side="left", padx=10)

        # 列表区域
        self.list_frame = ctk.CTkScrollableFrame(self, fg_color="transparent")
        self.list_frame.pack(fill="both", expand=True, padx=12, pady=4)

        # 空状态占位
        self._placeholder = ctk.CTkLabel(self.list_frame, text="拖放图片到此处，或点击「添加图片」",
                                          font=("", 14), text_color="gray")
        self._placeholder.pack(expand=True)

        # 底部
        bottom = ctk.CTkFrame(self, fg_color="transparent")
        bottom.pack(fill="x", padx=12, pady=(4, 8))

        self.overwrite_var = ctk.BooleanVar(value=self.cfg.get("overwrite", False))
        ctk.CTkCheckBox(bottom, text="覆盖原文件", variable=self.overwrite_var,
                         font=("", 11)).pack(side="left")
        ctk.CTkLabel(bottom, text="中质量：本地压缩  |  高质量：网络压缩",
                      text_color="gray", font=("", 10)).pack(side="right")

    # ============ 列表操作 ============

    def add_files(self):
        files = filedialog.askopenfilenames(
            title="选择图片", filetypes=[("图片", "*.png *.jpg *.jpeg")]
        )
        for f in files:
            size = os.path.getsize(f)
            item = {
                "path": f, "format": "none", "quality": "high",
                "resize": 0, "_size": size
            }
            self.items.append(item)
            row = ImageRow(self.list_frame, item,
                           on_remove=lambda r=item: self._remove_item(r),
                           on_change=self._save_items)
            row.pack(fill="x", pady=2, padx=2)
            self.row_widgets.append(row)
        self._update_ui()

    def clear_list(self):
        for w in self.row_widgets:
            w.destroy()
        self.row_widgets.clear()
        self.items.clear()
        self._update_ui()

    def _remove_item(self, item):
        idx = next(i for i, it in enumerate(self.items) if it["path"] == item["path"])
        self.row_widgets[idx].destroy()
        del self.row_widgets[idx]
        del self.items[idx]
        self._update_ui()

    def _save_items(self):
        pass  # items 直接引用，无需保存

    def _update_ui(self):
        n = len(self.items)
        self.status_label.configure(text=f"共 {n} 张图片" if n else "拖放或点击添加图片")
        if n:
            self._placeholder.pack_forget()
        else:
            self._placeholder.pack(expand=True)
        self.btn_start.configure(state="normal" if n and not self.running else "disabled")

    # ============ 压缩 ============

    def start_compression(self):
        if self.running:
            self.running = False
            self.btn_start.configure(text="▶ 马上压缩")
            return
        if not self.items:
            return

        self.running = True
        self.btn_start.configure(text="■ 停止", fg_color="red")
        self.cfg["overwrite"] = self.overwrite_var.get()
        save_config(self.cfg)

        thread = threading.Thread(target=self._run_compression, daemon=True)
        thread.start()

    def _run_compression(self):
        overwrite = self.overwrite_var.get()
        api_key = self.cfg.get("api_key", "")
        backup_key = self.cfg.get("backup_api_key", "")

        for i, item in enumerate(self.items):
            if not self.running:
                break

            input_path = item["path"]
            fmt = item["format"]
            quality = item["quality"]
            resize_px = item["resize"]
            ext = Path(input_path).suffix.lower()

            self._set_status(i, "🔄")
            logger.logger.info(f"[{i+1}/{len(self.items)}] {Path(input_path).name} fmt={fmt} q={quality} resize={resize_px}")

            try:
                tmp = input_path + ".liteimage.tmp"
                out_ext = { "jpg2png": ".png", "png2jpg": ".jpg" }.get(fmt, ext)
                out_path = input_path if overwrite else str(
                    Path(input_path).with_name(Path(input_path).stem + "-compressed" + out_ext))

                # 缩放
                work_file = input_path
                if resize_px > 0:
                    tmp_r = input_path + ".resize.tmp"
                    compressor.resize_by_long_edge(input_path, tmp_r, resize_px)
                    work_file = tmp_r

                # 格式转换 + 压缩
                if fmt == "png2jpg":
                    compressor.convert_to_jpeg(work_file, tmp, quality={"medium":80,"high":90,"none":95}[quality])
                elif quality == "high" and ext == ".png" and fmt == "none" and api_key:
                    try:
                        compressor.tinypng_compress(work_file, tmp, api_key)
                    except Exception:
                        if backup_key:
                            try:
                                compressor.tinypng_compress(work_file, tmp, backup_key)
                            except Exception:
                                compressor.compress_png(work_file, tmp, "high")
                        else:
                            compressor.compress_png(work_file, tmp, "high")
                elif fmt == "jpg2png":
                    t = tmp + ".png"
                    compressor.convert_to_png(work_file, t)
                    compressor.posterize(t, tmp, quality=80)
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

                new_size = os.path.getsize(out_path)
                self._set_status(i, "✅")
                logger.logger.info(f"  ✅ {Path(input_path).name} → {new_size:,.0f}")

            except Exception as e:
                self._set_status(i, "❌")
                logger.logger.error(f"  ❌ {Path(input_path).name}: {e}")

        self.running = False
        self.btn_start.configure(text="▶ 马上压缩", fg_color=("#3B8ED0", "#1F6AA5"), state="normal")

    def _set_status(self, idx, icon):
        if idx < len(self.row_widgets):
            self.row_widgets[idx].status_label.configure(text=icon)

    # ============ 设置 ============

    def open_settings(self):
        dlg = ctk.CTkToplevel(self)
        dlg.title("设置")
        dlg.geometry("440x480")
        dlg.transient(self)
        dlg.grab_set()

        tab = ctk.CTkTabview(dlg)
        tab.pack(fill="both", expand=True, padx=8, pady=8)
        tab.add("API Key")
        tab.add("Debug")

        # API Key
        api_frame = tab.tab("API Key")
        ctk.CTkLabel(api_frame, text="主 API Key:", font=("", 12)).pack(anchor="w", padx=10, pady=(10, 2))
        api_var = ctk.StringVar(value=self.cfg.get("api_key", ""))
        ctk.CTkEntry(api_frame, textvariable=api_var, width=380, show="•").pack(padx=10)

        ctk.CTkLabel(api_frame, text="备用 API Key:", font=("", 12)).pack(anchor="w", padx=10, pady=(10, 2))
        backup_var = ctk.StringVar(value=self.cfg.get("backup_api_key", ""))
        ctk.CTkEntry(api_frame, textvariable=backup_var, width=380, show="•").pack(padx=10)

        def test_key(var, label):
            try:
                valid, count = compressor.tinypng_validate(var.get())
                label.configure(text=f"✅ 有效，本月已用 {count} 次" if valid else "❌ 无效",
                                text_color="green" if valid else "red")
            except Exception as e:
                label.configure(text=f"❌ {e}", text_color="red")

        t1 = ctk.CTkFrame(api_frame, fg_color="transparent")
        t1.pack(fill="x", padx=10, pady=4)
        ctk.CTkButton(t1, text="测试主 Key", width=100, command=lambda: test_key(api_var, api_status)).pack(side="left")
        api_status = ctk.CTkLabel(t1, text="", font=("", 10))
        api_status.pack(side="left", padx=8)

        t2 = ctk.CTkFrame(api_frame, fg_color="transparent")
        t2.pack(fill="x", padx=10, pady=4)
        ctk.CTkButton(t2, text="测试备用 Key", width=100, command=lambda: test_key(backup_var, backup_status)).pack(side="left")
        backup_status = ctk.CTkLabel(t2, text="", font=("", 10))
        backup_status.pack(side="left", padx=8)

        def restore():
            api_var.set(DEFAULT_API_KEY)
            backup_var.set(DEFAULT_BACKUP_KEY)
        ctk.CTkButton(api_frame, text="🔄 还原默认 Key", fg_color="transparent",
                       border_width=1, command=restore).pack(pady=6)

        ctk.CTkButton(api_frame, text="🔗 申请免费 API Key →",
                       fg_color="transparent", text_color=("#3B8ED0", "#1F6AA5"),
                       command=lambda: webbrowser.open("https://tinypng.com/developers")).pack()

        # Debug
        debug_frame = tab.tab("Debug")
        debug_var = ctk.BooleanVar(value=self.cfg.get("debug_log", False))
        ctk.CTkCheckBox(debug_frame, text="启用 Debug 日志", variable=debug_var).pack(anchor="w", padx=10, pady=10)

        def open_log():
            os.startfile(logger.get_log_dir()) if os.name == "nt" else None
        ctk.CTkButton(debug_frame, text="📂 打开日志目录", fg_color="transparent",
                       border_width=1, command=open_log).pack(padx=10, pady=4)
        ctk.CTkButton(debug_frame, text="📄 查看最新日志", fg_color="transparent",
                       border_width=1, command=lambda: os.startfile(logger.get_log_path()) if os.path.exists(logger.get_log_path()) else messagebox.showinfo("提示","暂无日志")).pack(padx=10, pady=4)

        def save():
            self.cfg["api_key"] = api_var.get()
            self.cfg["backup_api_key"] = backup_var.get()
            self.cfg["debug_log"] = debug_var.get()
            save_config(self.cfg)
            logger.enable(debug_var.get())
            dlg.destroy()

        ctk.CTkButton(dlg, text="💾 保存设置", command=save).pack(pady=10)


if __name__ == "__main__":
    app = LiteImageApp()
    app.mainloop()
