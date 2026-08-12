#!/usr/bin/env python3
"""轻图 Windows — 图片压缩 & 格式转换工具"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
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


class LiteImageApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("轻图 Windows")
        self.geometry("820x620")
        self.minsize(700, 500)
        self.cfg = load_config()
        self.items = []  # [(path, format_mode, quality_mode, resize_px)]
        self.running = False
        self._build_ui()
        logger.enable(self.cfg.get("debug_log", False))

    def _build_ui(self):
        # === 工具栏 ===
        toolbar = ttk.Frame(self)
        toolbar.pack(fill=tk.X, padx=10, pady=(10, 0))

        ttk.Button(toolbar, text="添加图片", command=self.add_files).pack(side=tk.LEFT, padx=2)
        ttk.Button(toolbar, text="清空列表", command=self.clear_list).pack(side=tk.LEFT, padx=2)
        ttk.Button(toolbar, text="⚙ 设置", command=self.open_settings).pack(side=tk.RIGHT, padx=2)

        self.btn_start = ttk.Button(toolbar, text="▶ 马上压缩", command=self.start_compression)
        self.btn_start.pack(side=tk.RIGHT, padx=2)

        ttk.Separator(self, orient=tk.HORIZONTAL).pack(fill=tk.X, padx=10, pady=5)

        # === 文件列表 ===
        cols = ("状态", "文件名", "大小", "格式转换", "质量", "缩放")
        self.tree = ttk.Treeview(self, columns=cols, show="headings", selectmode="extended")
        self.tree.pack(fill=tk.BOTH, expand=True, padx=10)

        widths = [50, 280, 80, 100, 80, 120]
        for col, w in zip(cols, widths):
            self.tree.heading(col, text=col, command=lambda c=col: self._on_col_click(c))
            self.tree.column(col, width=w, anchor="center" if col != "文件名" else "w")

        self.tree.bind("<Double-1>", self._on_double_click)
        self.tree.bind("<Delete>", lambda e: self.remove_selected())

        # === 右键菜单 ===
        self.menu = tk.Menu(self, tearoff=0)
        self.menu.add_command(label="设置格式 → 不转换", command=lambda: self._set_format("none"))
        self.menu.add_command(label="设置格式 → JPG→PNG", command=lambda: self._set_format("jpg2png"))
        self.menu.add_command(label="设置格式 → PNG→JPG", command=lambda: self._set_format("png2jpg"))
        self.menu.add_separator()
        self.menu.add_command(label="质量 → 不压缩", command=lambda: self._set_quality("none"))
        self.menu.add_command(label="质量 → 中等质量", command=lambda: self._set_quality("medium"))
        self.menu.add_command(label="质量 → 高质量", command=lambda: self._set_quality("high"))
        self.menu.add_separator()
        self.menu.add_command(label="缩放 → 1920px", command=lambda: self._set_resize(1920))
        self.menu.add_command(label="缩放 → 1280px", command=lambda: self._set_resize(1280))
        self.menu.add_command(label="缩放 → 800px", command=lambda: self._set_resize(800))
        self.menu.add_command(label="缩放 → 关闭", command=lambda: self._set_resize(0))
        self.menu.add_separator()
        self.menu.add_command(label="移除选中", command=self.remove_selected)
        self.tree.bind("<Button-3>", self._show_menu)

        # === 底部 ===
        bottom = ttk.Frame(self)
        bottom.pack(fill=tk.X, padx=10, pady=(0, 5))
        self.status_var = tk.StringVar(value="就绪")
        ttk.Label(bottom, textvariable=self.status_var, foreground="gray").pack(side=tk.LEFT)
        ttk.Label(bottom, text="中质量：本地压缩 | 高质量：网络压缩",
                  foreground="gray", font=("", 9)).pack(side=tk.RIGHT)

        # === 覆盖原文件 ===
        chk = ttk.Frame(self)
        chk.pack(fill=tk.X, padx=10)
        self.overwrite_var = tk.BooleanVar(value=self.cfg.get("overwrite", False))
        ttk.Checkbutton(chk, text="覆盖原文件", variable=self.overwrite_var).pack(side=tk.LEFT)
        ttk.Label(chk, text="(勾选后直接替换，不勾选保存为 xxx-compressed.xxx)",
                  foreground="gray", font=("", 9)).pack(side=tk.LEFT, padx=5)

    # ============ 列表操作 ============

    def add_files(self):
        files = filedialog.askopenfilenames(
            title="选择图片", filetypes=[("图片", "*.png *.jpg *.jpeg")]
        )
        for f in files:
            ext = Path(f).suffix.lower()
            fmt = "jpg2png" if ext in (".jpg", ".jpeg") else "none"
            size = os.path.getsize(f)
            self.tree.insert("", tk.END, values=(
                "⏳", Path(f).name, self._fmt_size(size),
                self._fmt_label(fmt), "高质量", "—"
            ))
            self.items.append({
                "path": f, "format": fmt, "quality": "high", "resize": 0
            })
        self._update_count()

    def clear_list(self):
        self.tree.delete(*self.tree.get_children())
        self.items.clear()
        self._update_count()

    def remove_selected(self):
        for sel in self.tree.selection():
            idx = self.tree.index(sel)
            self.tree.delete(sel)
            del self.items[idx]
        self._update_count()

    def _update_count(self):
        n = len(self.items)
        self.status_var.set(f"共 {n} 张图片" if n else "就绪")
        self.btn_start.config(state=tk.NORMAL if n and not self.running else tk.DISABLED)

    # ============ 右键菜单 ============

    def _show_menu(self, event):
        if self.tree.selection():
            self.menu.post(event.x_root, event.y_root)

    def _set_format(self, mode):
        for sel in self.tree.selection():
            idx = self.tree.index(sel)
            self.items[idx]["format"] = mode
            self.tree.set(sel, column="格式转换", value=self._fmt_label(mode))

    def _set_quality(self, mode):
        for sel in self.tree.selection():
            idx = self.tree.index(sel)
            self.items[idx]["quality"] = mode
            label = {"none": "不压缩", "medium": "中等质量", "high": "高质量"}[mode]
            self.tree.set(sel, column="质量", value=label)

    def _set_resize(self, px):
        for sel in self.tree.selection():
            idx = self.tree.index(sel)
            self.items[idx]["resize"] = px
            label = f"{px}px" if px else "—"
            self.tree.set(sel, column="缩放", value=label)

    def _on_double_click(self, event):
        """双击修改缩放值"""
        sel = self.tree.selection()
        if not sel:
            return
        idx = self.tree.index(sel[0])

        dlg = tk.Toplevel(self)
        dlg.title("设置缩放")
        dlg.geometry("250x100")
        dlg.transient(self)
        dlg.grab_set()

        ttk.Label(dlg, text="长边像素（0=关闭）：").pack(pady=5)
        var = tk.IntVar(value=self.items[idx].get("resize", 0))
        ttk.Entry(dlg, textvariable=var, width=10).pack()
        ttk.Button(dlg, text="确定", command=lambda: [
            self.items[idx].update({"resize": var.get()}),
            self.tree.set(sel[0], column="缩放", value=f"{var.get()}px" if var.get() else "—"),
            dlg.destroy()
        ]).pack()

    def _on_col_click(self, col):
        """点击列头排序"""
        pass  # 暂不实现

    # ============ 压缩 ============

    def start_compression(self):
        if self.running:
            self.running = False
            self.btn_start.config(text="▶ 马上压缩", state=tk.DISABLED)
            return
        if not self.items:
            return

        self.running = True
        self.btn_start.config(text="■ 停止")
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

                # 决定输出格式
                if fmt == "jpg2png":
                    out_ext = ".png"
                elif fmt == "png2jpg":
                    out_ext = ".jpg"
                else:
                    out_ext = ext

                out_path = input_path if overwrite else str(Path(input_path).with_name(
                    Path(input_path).stem + "-compressed" + out_ext
                ))

                # 缩放
                work_file = input_path
                if resize_px > 0:
                    tmp_resize = input_path + ".resize.tmp"
                    compressor.resize_by_long_edge(input_path, tmp_resize, resize_px)
                    work_file = tmp_resize

                # 格式转换 + 压缩
                if fmt == "png2jpg":
                    compressor.convert_to_jpeg(work_file, tmp, quality={"medium": 80, "high": 90, "none": 95}[quality])
                elif quality == "high" and ext == ".png" and fmt == "none" and api_key:
                    # 尝试 TinyPNG
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
                    compressor.convert_to_png(work_file, tmp)
                    if quality != "none":
                        compressor.oxipng_optimize(tmp)
                    # Posterizer
                    tmp2 = tmp + ".poster.png"
                    if compressor.posterize(tmp, tmp2, quality=80):
                        os.replace(tmp2, tmp)
                        compressor.oxipng_optimize(tmp)
                elif ext in (".png",) and fmt == "none":
                    compressor.compress_png(work_file, tmp, quality)
                else:
                    compressor.compress_jpg(work_file, tmp, quality)

                # 移动结果
                if os.path.exists(out_path) and overwrite:
                    os.remove(out_path)
                os.replace(tmp, out_path)

                # 清理
                for f in [work_file if work_file != input_path else None]:
                    if f and os.path.exists(f) and f != out_path:
                        os.remove(f)

                new_size = os.path.getsize(out_path)
                self._set_status(i, "✅")
                logger.logger.info(f"  ✅ {Path(input_path).name} → {new_size:,.0f} bytes")

            except Exception as e:
                self._set_status(i, "❌")
                logger.logger.error(f"  ❌ {Path(input_path).name}: {e}")

        self.running = False
        self.btn_start.config(text="▶ 马上压缩", state=tk.NORMAL)

    def _set_status(self, idx, icon):
        self.tree.set(self.tree.get_children()[idx], column="状态", value=icon)

    # ============ 设置 ============

    def open_settings(self):
        dlg = tk.Toplevel(self)
        dlg.title("设置")
        dlg.geometry("420x400")
        dlg.transient(self)
        dlg.grab_set()

        notebook = ttk.Notebook(dlg)
        notebook.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

        # === API Key 页 ===
        api_frame = ttk.Frame(notebook)
        notebook.add(api_frame, text="API Key")

        ttk.Label(api_frame, text="主 API Key:").pack(anchor=tk.W, padx=10, pady=(10, 0))
        api_var = tk.StringVar(value=self.cfg.get("api_key", ""))
        ttk.Entry(api_frame, textvariable=api_var, width=50, show="*").pack(padx=10)

        ttk.Label(api_frame, text="备用 API Key:").pack(anchor=tk.W, padx=10, pady=(10, 0))
        backup_var = tk.StringVar(value=self.cfg.get("backup_api_key", ""))
        ttk.Entry(api_frame, textvariable=backup_var, width=50, show="*").pack(padx=10)

        def test_key(var, label):
            try:
                valid, count = compressor.tinypng_validate(var.get())
                label.config(text=f"✅ 有效，本月已用 {count} 次" if valid else "❌ 无效", foreground="green" if valid else "red")
            except Exception as e:
                label.config(text=f"❌ {e}", foreground="red")

        ttk.Button(api_frame, text="测试主 Key", command=lambda: test_key(api_var, api_status)).pack(pady=2)
        api_status = ttk.Label(api_frame, text="")
        api_status.pack()

        ttk.Button(api_frame, text="测试备用 Key", command=lambda: test_key(backup_var, backup_status)).pack(pady=2)
        backup_status = ttk.Label(api_frame, text="")
        backup_status.pack()

        ttk.Button(api_frame, text="🔗 申请免费 API Key",
                   command=lambda: webbrowser.open("https://tinypng.com/developers")).pack(pady=5)

        # === Debug 页 ===
        debug_frame = ttk.Frame(notebook)
        notebook.add(debug_frame, text="Debug")

        debug_var = tk.BooleanVar(value=self.cfg.get("debug_log", False))
        ttk.Checkbutton(debug_frame, text="启用 Debug 日志", variable=debug_var).pack(anchor=tk.W, padx=10, pady=10)

        def open_log():
            os.startfile(logger.get_log_dir())
        ttk.Button(debug_frame, text="📂 打开日志目录", command=open_log).pack(padx=10, pady=2)

        def view_log():
            if os.path.exists(logger.get_log_path()):
                os.startfile(logger.get_log_path())
            else:
                messagebox.showinfo("提示", "暂无日志文件")
        ttk.Button(debug_frame, text="📄 查看最新日志", command=view_log).pack(padx=10, pady=2)

        # === 保存 ===
        def save():
            self.cfg["api_key"] = api_var.get()
            self.cfg["backup_api_key"] = backup_var.get()
            self.cfg["debug_log"] = debug_var.get()
            save_config(self.cfg)
            logger.enable(debug_var.get())
            dlg.destroy()

        def restore():
            api_var.set(DEFAULT_API_KEY)
            backup_var.set(DEFAULT_BACKUP_KEY)

        ttk.Button(api_frame, text="🔄 还原默认 Key", command=restore).pack(pady=2)

        ttk.Button(dlg, text="💾 保存设置", command=save).pack(pady=10)

    # ============ 辅助 ============

    @staticmethod
    def _fmt_size(size):
        if size < 1024:
            return f"{size} B"
        elif size < 1024 * 1024:
            return f"{size / 1024:.1f} KB"
        else:
            return f"{size / (1024 * 1024):.1f} MB"

    @staticmethod
    def _fmt_label(mode):
        return {"none": "不转换", "jpg2png": "JPG→PNG", "png2jpg": "PNG→JPG"}.get(mode, mode)


if __name__ == "__main__":
    app = LiteImageApp()
    app.mainloop()
