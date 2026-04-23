import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import type { VideoInfo, GifResult } from "../types";
import "./VideoToGif.css";

function fmtSize(b: number) {
  if (b < 1024) return `${b} B`;
  if (b < 1048576) return `${(b / 1024).toFixed(1)} KB`;
  return `${(b / 1048576).toFixed(1)} MB`;
}

function fmtDur(s: number) {
  const m = Math.floor(s / 60), sec = Math.floor(s % 60);
  return `${String(m).padStart(2,"0")}:${String(sec).padStart(2,"0")}`;
}

const QUALITIES = [
  { key: "low", label: "低质量", v: 50 },
  { key: "mid", label: "中等",   v: 70 },
  { key: "hi",  label: "高质量", v: 90 },
];

interface VItem {
  id: string;
  path: string;
  info: VideoInfo | null;
  st: "wait" | "run" | "ok" | "err";
  res?: GifResult;
  err?: string;
}

export default function VideoToGif() {
  const [vs, setVs] = useState<VItem[]>([]);
  const [q, setQ] = useState(70);
  const [w, setW] = useState(480);
  const [f, setF] = useState(25);
  const [busy, setBusy] = useState(false);
  const [drag, setDrag] = useState(false);

  const pend = vs.filter(v => v.st === "wait").length;
  const done = vs.filter(v => v.st === "ok").length;
  const fail = vs.filter(v => v.st === "err").length;

  useEffect(() => {
    const u1 = listen<{ paths: string[] }>("tauri://drag-drop", e => {
      if (e.payload.paths?.length) add(e.payload.paths);
    });
    const u2 = listen("tauri://drag-hover", () => setDrag(true));
    const u3 = listen("tauri://drag-cancel", () => setDrag(false));
    const u4 = listen("tauri://drag-drop", () => setDrag(false));
    return () => {
      u1.then(f => f()); u2.then(f => f()); u3.then(f => f()); u4.then(f => f());
    };
  }, []);

  async function getInfo(p: string): Promise<VideoInfo | null> {
    try { 
      return await invoke<VideoInfo>("get_video_info", { inputPath: p });
    } catch (e) { 
      return null; 
    }
  }

  async function add(paths: string[]) {
    const videoExts = ["mp4","mov","m4v","avi","mkv","webm"];
    const allExts = [...videoExts, "gif"];
    const ok = paths.filter(p => allExts.includes(p.split(".").pop()!.toLowerCase()));
    if (!ok.length) return;

    const neu: VItem[] = ok.map(p => ({ id: crypto.randomUUID(), path: p, info: null, st: "wait" as const }));
    setVs(prev => [...prev, ...neu]);

    for (let i = 0; i < ok.length; i++) {
      const info = await getInfo(ok[i]);
      setVs(prev => prev.map(v => v.id === neu[i].id ? { ...v, info } : v));
      // 第一个文件自动填充宽度和帧率
      if (i === 0 && info) {
        setW(Math.max(Math.min(info.width, 1280), 160));
        setF(Math.max(Math.round(info.fps), 5));
      }
    }
  }

  async function pick() {
    try {
      const s = await open({
        multiple: true,
        filters: [{ name: "视频/GIF", extensions: ["mp4","mov","m4v","avi","mkv","webm","gif"] }],
      });
      if (s?.length) add(s as string[]);
    } catch {}
  }

  function rm(id: string) { setVs(prev => prev.filter(v => v.id !== id)); }
  function clr() { setVs([]); }

  async function start() {
    const pendV = vs.filter(v => v.st === "wait");
    if (!pendV.length) return;
    setBusy(true);

    for (const v of pendV) {
      setVs(prev => prev.map(x => x.id === v.id ? { ...x, st: "run" as const } : x));
      try {
        const r = await invoke<GifResult>("convert_video_to_gif", {
          inputPath: v.path, quality: q, width: w, fps: f,
          startTime: 0, duration: v.info?.duration || 5,
        });
        setVs(prev => prev.map(x => x.id === v.id ? { ...x, st: "ok" as const, res: r } : x));
      } catch (e) {
        setVs(prev => prev.map(x => x.id === v.id ? { ...x, st: "err" as const, err: String(e) } : x));
      }
    }
    setBusy(false);
  }

  function showInExp(p: string) { invoke("open_file_in_explorer", { path: p }).catch(() => {}); }
  function fn(p: string) { return p.split(/[/\\]/).pop() || p; }

  // 状态映射
  const statusIcon: Record<string, string> = { ok: "✅", err: "❌", run: "⏳", wait: "🎥" };
  const cls = (st: string) => `vg-item vg-item--${st}`;

  return (
    <div className="vg-page">
      {/* 拖放区 */}
      <div className={`vg-drop ${drag ? "active-drag" : ""}`} onClick={pick}>
        <div className="vg-drop-icon">🎬</div>
        <div className="vg-drop-title">拖放视频文件到这里</div>
        <div className="vg-drop-desc">支持批量添加多个视频文件</div>
        <div className="vg-drop-hint">MP4 · MOV · M4V · AVI · MKV · WebM</div>
      </div>

      {/* 内容区 */}
      <div className="vg-body">
        {/* 视频列表 */}
        {vs.length > 0 && (
          <div className="vg-card">
            <div className="vg-list-header">
              <span className="vg-list-title">已添加 {vs.length} 个视频</span>
              <div className="vg-list-actions">
                {done > 0 && <span className="vg-badge vg-badge--ok">{done} 成功</span>}
                {fail > 0 && <span className="vg-badge vg-badge--err">{fail} 失败</span>}
                <button className="vg-btn-clear" onClick={clr}>清空全部</button>
              </div>
            </div>
            <div className="vg-list">
              {vs.map(v => (
                <div key={v.id} className={cls(v.st)}>
                  <span className="vg-item-emoji">{statusIcon[v.st]}</span>
                  <div className="vg-item-info">
                    <div className="vg-item-name">{fn(v.path)}</div>
                    {v.info && <div className="vg-item-meta">{v.info.width}×{v.info.height} · {fmtDur(v.info.duration)}</div>}
                    {v.st === "ok" && v.res && (
                      <div className="vg-item-sub vg-item-sub--ok">📦 {fn(v.res.output_path)} ({fmtSize(v.res.file_size)})</div>
                    )}
                    {v.st === "err" && <div className="vg-item-sub vg-item-sub--err" title={v.err}>{v.err}</div>}
                    {(v.st === "wait" || v.st === "run") && (
                      <div className="vg-item-sub vg-item-sub--idle">{v.st === "run" ? "⚙️ 转换中..." : "⏸ 等待转换"}</div>
                    )}
                  </div>
                  <div className="vg-item-btns">
                    {v.st === "ok" && v.res && (
                      <button className="vg-icon-btn vg-icon-btn--dir" onClick={() => showInExp(v.res!.output_path)} title="打开文件夹">📁</button>
                    )}
                    {(v.st === "wait" || v.st === "err") && (
                      <button className="vg-icon-btn vg-icon-btn--del" onClick={() => rm(v.id)} title="移除">✕</button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* 设置面板 */}
        <div className="vg-card">
          <div className="vg-settings-header">
            <span className="emoji">⚙️</span>
            <h3>转换设置</h3>
          </div>

          <div className="vg-section">
            <div className="vg-section-label">输出质量</div>
            <div className="vg-quality-row">
              {QUALITIES.map(p => (
                <button
                  key={p.key}
                  className={`vg-quality-btn ${q === p.v ? "on" : ""}`}
                  onClick={() => setQ(p.v)}
                >{p.label}</button>
              ))}
            </div>
          </div>

          <div className="vg-section">
            <div className="vg-section-label">输出尺寸</div>
            <div className="vg-slider">
              <div className="vg-slider-head">
                <span className="vg-slider-label">宽度</span>
                <span className="vg-slider-val">{w} px</span>
              </div>
              <input type="range" min={160} max={1280} step={40} value={w}
                     onChange={e => setW(+e.target.value)} className="vg-range" />
            </div>
            <div className="vg-slider">
              <div className="vg-slider-head">
                <span className="vg-slider-label">帧率</span>
                <span className="vg-slider-val">{f} FPS</span>
              </div>
              <input type="range" min={5} max={30} step={5} value={f}
                     onChange={e => setF(+e.target.value)} className="vg-range" />
            </div>
          </div>

          {/* 链接区域 */}
          <div className="vg-links">
            <a href="https://my.feishu.cn/wiki/HsGqwApFRiAkBTkEogicP47VnxF?from=from_copylink" target="_blank" rel="noopener noreferrer">飞书文档</a>
            <span className="vg-link-sep">|</span>
            <a href="https://github.com/Ziloong/Liteimage" target="_blank" rel="noopener noreferrer">Github 仓库</a>
          </div>
        </div>
      </div>

      {/* 底部操作栏 */}
      <div className="vg-footer">
        {busy
          ? (<div className="vg-progress"><div className="vg-spinner"/><span className="vg-progress-label">正在转换 {done + 1}/{pend + done}...</span></div>)
          : (<>
              <button className="vg-start-btn" onClick={start} disabled={!pend}>
                ▶ 开始转换{pend ? ` (${pend})` : ""}
              </button>
              {done > 0 && <span className="vg-status-text">✅ 已完成 {done} 个</span>}
              {fail > 0 && <span className="vg-status-text vg-status-text--err">❌ 失败 {fail} 个</span>}
            </>)
        }
      </div>
    </div>
  );
}
