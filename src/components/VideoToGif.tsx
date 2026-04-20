import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import type { VideoInfo, GifResult } from "../types";

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDuration(seconds: number): string {
  const min = Math.floor(seconds / 60);
  const sec = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 100);
  return `${String(min).padStart(2, "0")}:${String(sec).padStart(2, "0")}.${String(ms).padStart(2, "0")}`;
}

const QUALITY_PRESETS = [
  { key: "low", label: "低", value: 50 },
  { key: "medium", label: "中", value: 70 },
  { key: "high", label: "高", value: 90 },
];

export default function VideoToGif() {
  const [videoPath, setVideoPath] = useState<string | null>(null);
  const [videoInfo, setVideoInfo] = useState<VideoInfo | null>(null);
  const [quality, setQuality] = useState(70);
  const [width, setWidth] = useState(480);
  const [fps, setFps] = useState(15);
  const [isConverting, setIsConverting] = useState(false);
  const [conversionLogs, setConversionLogs] = useState<string[]>([]);
  const [gifResult, setGifResult] = useState<GifResult | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  const addLog = (msg: string) => {
    const time = new Date().toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    setConversionLogs((prev) => [...prev, `[${time}] ${msg}`]);
  };

  // Drag and drop for video
  useEffect(() => {
    const unlisten = listen<{ paths: string[] }>("tauri://drag-drop", (event) => {
      const path = event.payload.paths[0];
      if (path) loadVideo(path);
    });
    const unlistenHover = listen("tauri://drag-hover", () => setIsDragging(true));
    const unlistenLeave = listen("tauri://drag-cancel", () => setIsDragging(false));
    const unlistenDrop = listen("tauri://drag-drop", () => setIsDragging(false));

    return () => {
      unlisten.then((fn) => fn());
      unlistenHover.then((fn) => fn());
      unlistenLeave.then((fn) => fn());
      unlistenDrop.then((fn) => fn());
    };
  }, []);

  const loadVideo = async (path: string) => {
    try {
      const info = await invoke<VideoInfo>("get_video_info", { inputPath: path });
      setVideoPath(path);
      setVideoInfo(info);
      setGifResult(null);
      setConversionLogs([]);
      if (info.width > 0) {
        setWidth(info.width);
      }
      addLog(`✅ 加载视频成功: ${path.split(/[/\\]/).pop()}`);
      addLog(`   分辨率: ${info.width}×${info.height}`);
      addLog(`   时长: ${formatDuration(info.duration)}`);
    } catch (err) {
      addLog(`❌ 读取视频信息失败: ${err}`);
    }
  };

  const handleSelectVideo = async () => {
    try {
      const selected = await open({
        multiple: false,
        filters: [
          {
            name: "视频",
            extensions: ["mp4", "mov", "m4v", "avi", "mkv", "webm"],
          },
        ],
      });
      if (selected) {
        loadVideo(selected as string);
      }
    } catch {}
  };

  const startConversion = async () => {
    if (!videoPath) {
      addLog("❌ 请先选择视频文件");
      return;
    }

    setIsConverting(true);
    setGifResult(null);
    addLog("开始转换...");
    addLog(`   质量: ${quality}`);
    addLog(`   宽度: ${width}px`);
    addLog(`   帧率: ${fps} FPS`);

    try {
      const result = await invoke<GifResult>("convert_video_to_gif", {
        inputPath: videoPath,
        quality,
        width,
        fps,
        startTime: 0,
        duration: videoInfo?.duration || 5,
      });

      setGifResult(result);
      addLog("✅ 转换成功!");
      addLog(`   输出: ${result.output_path.split(/[/\\]/).pop()}`);
      addLog(`   大小: ${formatSize(result.file_size)}`);
    } catch (err) {
      addLog(`❌ 转换失败: ${err}`);
    } finally {
      setIsConverting(false);
    }
  };

  const showInExplorer = async (path: string) => {
    try {
      await invoke("open_file_in_explorer", { path });
    } catch {}
  };

  return (
    <div className="gif-page">
      <div className="gif-layout">
        {/* Preview / Drop Zone */}
        <div className="gif-preview">
          {!videoPath ? (
            <div
              className={`drop-zone ${isDragging ? "dragging" : ""}`}
              onClick={handleSelectVideo}
              style={{ height: "220px" }}
            >
              <div className="drop-icon">🎬</div>
              <div className="drop-title">拖放视频文件到这里</div>
              <div className="drop-subtitle">或点击选择文件</div>
              <div className="drop-hint">支持 MP4, MOV, M4V</div>
            </div>
          ) : (
            <div
              className={`drop-zone ${isDragging ? "dragging" : ""}`}
              style={{ height: "180px" }}
              onClick={handleSelectVideo}
            >
              <div className="drop-icon" style={{ fontSize: 48 }}>🎥</div>
              <div className="drop-title">{videoPath.split(/[/\\]/).pop()}</div>
            </div>
          )}

          {videoInfo && (
            <div className="video-info">
              <div className="video-name">{videoPath!.split(/[/\\]/).pop()}</div>
              <div className="video-details">
                <span>📐 {videoInfo.width}×{videoInfo.height}</span>
                <span>⏱ {formatDuration(videoInfo.duration)}</span>
                <span>🎬 {videoInfo.fps.toFixed(1)} FPS</span>
              </div>
            </div>
          )}
        </div>

        {/* Settings Panel */}
        <div className="gif-settings-panel">
          <div className="settings-title">质量</div>
          <div className="quality-bar" style={{ padding: 0, marginBottom: 12 }}>
            {QUALITY_PRESETS.map((preset) => (
              <button
                key={preset.key}
                className={`quality-btn ${quality === preset.value ? "active" : ""}`}
                onClick={() => setQuality(preset.value)}
              >
                {preset.label}
              </button>
            ))}
          </div>

          <div className="settings-subtitle">输出设置</div>

          <div className="slider-row">
            <div className="slider-header">
              <span className="slider-label">宽度</span>
              <span className="slider-value">{width} px</span>
            </div>
            <input
              type="range"
              min={160}
              max={1280}
              step={40}
              value={width}
              onChange={(e) => setWidth(parseInt(e.target.value))}
            />
          </div>

          <div className="slider-row">
            <div className="slider-header">
              <span className="slider-label">帧率</span>
              <span className="slider-value">{fps} FPS</span>
            </div>
            <input
              type="range"
              min={5}
              max={30}
              step={5}
              value={fps}
              onChange={(e) => setFps(parseInt(e.target.value))}
            />
          </div>
        </div>
      </div>

      {/* Action Buttons */}
      <div className="action-bar">
        {!isConverting ? (
          <>
            <button
              className="btn btn-primary"
              onClick={startConversion}
              disabled={!videoPath}
            >
              ▶ 开始转换
            </button>
          </>
        ) : (
          <>
            <div className="progress-bar-container">
              <div className="progress-bar">
                <div
                  className="progress-bar-fill"
                  style={{ width: "100%", animation: "pulse 1.5s infinite" }}
                />
              </div>
            </div>
            <button className="btn btn-danger">⏹ 停止</button>
          </>
        )}
      </div>

      {/* Log */}
      <div className="conversion-log">
        <div className="log-header">日志</div>
        <div className={`log-box ${conversionLogs.length === 0 ? "placeholder" : ""}`}>
          {conversionLogs.length === 0
            ? "等待转换..."
            : conversionLogs.join("\n")}
        </div>
      </div>

      {/* Output Result */}
      {gifResult && (
        <div className="output-bar">
          <span className="output-success">✅ 转换完成</span>
          <button
            className="btn"
            onClick={() => showInExplorer(gifResult.output_path)}
          >
            📁 在文件夹中显示
          </button>
        </div>
      )}
    </div>
  );
}
