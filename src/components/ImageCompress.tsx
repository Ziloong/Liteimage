import React, { useState, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import type { CompressResult } from "../types";

interface LogEntry {
  id: string;
  timestamp: Date;
  filename: string;
  originalSize: number;
  compressedSize: number;
  status: "waiting" | "compressing" | "success" | "failed";
  message?: string;
  extension: string;
}

interface ImageInfo {
  width: number;
  height: number;
  size: number;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

const QUALITY_PRESETS = [
  { key: "ultraLow", label: "超低", range: "10-20" },
  { key: "low", label: "低", range: "40-60" },
  { key: "medium", label: "中", range: "65-80" },
  { key: "high", label: "高", range: "85-95" },
];

export default function ImageCompress() {
  const [engine, setEngine] = useState<"local" | "tinyPNG">("local");
  const [overwrite, setOverwrite] = useState(true);
  const [quality, setQuality] = useState("65-80");
  const [resizeEnabled, setResizeEnabled] = useState(false);
  const [maxLongEdge, setMaxLongEdge] = useState(1920);
  const [lastImportedPath, setLastImportedPath] = useState<string | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const [, setApiKey] = useState<string | null>(null);

  const dropRef = useRef<HTMLDivElement>(null);

  const totalCompressed = logs.filter((l) => l.status === "success").length;
  const totalSaved = logs
    .filter((l) => l.status === "success")
    .reduce((sum, l) => sum + (l.originalSize - l.compressedSize), 0);
  const avgRatio =
    totalCompressed > 0
      ? logs
          .filter((l) => l.status === "success")
          .reduce((sum, l) => {
            if (l.originalSize === 0) return sum;
            return sum + ((l.originalSize - l.compressedSize) / l.originalSize) * 100;
          }, 0) / totalCompressed
      : 0;

  // Load API key on mount
  React.useEffect(() => {
    invoke<string | null>("get_stored_api_key").then(setApiKey);
  }, []);

  // Drag and drop
  React.useEffect(() => {
    const unlisten = listen<{ paths: string[] }>("tauri://drag-drop", (event) => {
      const paths = event.payload.paths;
      const imageExts = ["png", "jpg", "jpeg"];
      const imageFiles = paths.filter(
        (p) => imageExts.includes(p.split(".").pop()?.toLowerCase() || "")
      );
      if (imageFiles.length > 0) handleFiles(imageFiles);
    });

    const unlistenHover = listen<{ paths: string[] }>("tauri://drag-hover", () =>
      setIsDragging(true)
    );
    const unlistenLeave = listen("tauri://drag-cancel", () => setIsDragging(false));
    const unlistenDrop = listen("tauri://drag-drop", () => setIsDragging(false));

    return () => {
      unlisten.then((fn) => fn());
      unlistenHover.then((fn) => fn());
      unlistenLeave.then((fn) => fn());
      unlistenDrop.then((fn) => fn());
    };
  }, [engine, overwrite, quality, resizeEnabled, maxLongEdge]);

  // 并行压缩处理函数
  const processInParallel = useCallback(
    async (
      paths: string[],
      newLogs: LogEntry[],
      setLogs: React.Dispatch<React.SetStateAction<LogEntry[]>>
    ) => {
      const CONCURRENCY = 4; // 并发数

      // 压缩单个文件
      const compressOne = async (path: string, logId: string) => {
        setLogs((prev) =>
          prev.map((l) => (l.id === logId ? { ...l, status: "compressing" as const } : l))
        );

        try {
          let result: CompressResult;
          if (engine === "tinyPNG") {
            result = await invoke<CompressResult>("compress_with_tinypng", {
              inputPath: path,
            });
          } else {
            result = await invoke<CompressResult>("compress_image", {
              inputPath: path,
              qualityRange: quality,
              overwrite,
              maxLongEdge: resizeEnabled ? maxLongEdge : 0,
            });
          }

          setLogs((prev) =>
            prev.map((l) =>
              l.id === logId
                ? {
                    ...l,
                    status: "success",
                    originalSize: result.original_size,
                    compressedSize: result.compressed_size,
                  }
                : l
            )
          );
        } catch (err) {
          setLogs((prev) =>
            prev.map((l) =>
              l.id === logId
                ? { ...l, status: "failed", message: String(err) }
                : l
            )
          );
        }
      };

      // 分批并发处理
      for (let i = 0; i < paths.length; i += CONCURRENCY) {
        const batch = paths.slice(i, i + CONCURRENCY);
        const batchLogs = newLogs.slice(i, i + CONCURRENCY);
        await Promise.all(
          batch.map((path, idx) => compressOne(path, batchLogs[idx].id))
        );
      }
    },
    [engine, overwrite, quality, resizeEnabled, maxLongEdge]
  );

  const handleFiles = useCallback(
    async (paths: string[]) => {
      const newLogs: LogEntry[] = paths.map((p) => {
        const parts = p.replace(/\\/g, "/").split("/");
        const filename = parts[parts.length - 1];
        const ext = (filename.split(".").pop() || "").toLowerCase();
        return {
          id: crypto.randomUUID(),
          timestamp: new Date(),
          filename,
          originalSize: 0,
          compressedSize: 0,
          status: "waiting" as const,
          extension: ext,
        };
      });

      setLogs((prev) => [...prev, ...newLogs]);

      // 并行处理
      await processInParallel(paths, newLogs, setLogs);
    },
    [engine, overwrite, quality, resizeEnabled, maxLongEdge, processInParallel]
  );

  const handleSelectFiles = async () => {
    try {
      const selected = await open({
        multiple: true,
        filters: [
          {
            name: "图片",
            extensions: ["png", "jpg", "jpeg"],
          },
        ],
      });
      if (selected && selected.length > 0) {
        // 保存最后一个文件的路径，用于自动获取最长边尺寸
        setLastImportedPath(selected[selected.length - 1]);
        handleFiles(selected as string[]);
      }
    } catch {}
  };

  const getFileIcon = (ext: string) => {
    switch (ext) {
      case "png":
        return "🖼";
      case "jpg":
      case "jpeg":
        return "🟠";
      default:
        return "📄";
    }
  };

  const copyToClipboard = (log: LogEntry) => {
    if (log.status !== "success") return;
    const ratio = ((1 - log.compressedSize / log.originalSize) * 100).toFixed(1);
    const text = `${log.filename}\n原始: ${formatSize(log.originalSize)} → 压缩: ${formatSize(log.compressedSize)}\n节省: ${ratio}%`;
    navigator.clipboard.writeText(text).catch(() => {});
  };

  return (
    <div className="compress-page">
      {/* Engine Selector */}
      <div className="engine-selector">
        <button
          className={`engine-btn ${engine === "local" ? "active" : ""}`}
          onClick={() => setEngine("local")}
        >
          <span className="engine-icon">⚡</span>
          本地引擎
        </button>
        <button
          className={`engine-btn ${engine === "tinyPNG" ? "active" : ""}`}
          onClick={() => setEngine("tinyPNG")}
        >
          <span className="engine-icon">☁</span>
          TinyPNG
        </button>
      </div>

      {/* Drop Zone */}
      <div
        ref={dropRef}
        className={`drop-zone ${isDragging ? "dragging" : ""}`}
        onClick={handleSelectFiles}
      >
        <div className="drop-icon">⬇</div>
        <div className="drop-title">拖放图片到此处</div>
        <div className="drop-subtitle">或点击选择图片文件</div>
        <div className="drop-hint">支持 PNG / JPG</div>
      </div>

      {/* Overwrite Option */}
      <div className="options-row">
        <label className="checkbox-label">
          <input
            type="checkbox"
            checked={overwrite}
            onChange={(e) => setOverwrite(e.target.checked)}
          />
          覆盖原文件
        </label>
        <span className="hint-text">
          {overwrite ? "压缩后直接替换原文件" : "压缩后保存为 xxx-compressed.xxx"}
        </span>
      </div>

      {/* Local Engine Options */}
      {engine === "local" && (
        <>
          <div className="quality-bar">
            <span className="label">质量：</span>
            {QUALITY_PRESETS.map((preset) => (
              <button
                key={preset.key}
                className={`quality-btn ${quality === preset.range ? "active" : ""}`}
                onClick={() => {
                  setQuality(preset.range);
                }}
              >
                {preset.label}
              </button>
            ))}
          </div>

          <div className="options-row">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={resizeEnabled}
                onChange={async (e) => {
                  const checked = e.target.checked;
                  if (checked && lastImportedPath) {
                    // 勾选时自动获取图片的最长边尺寸
                    try {
                      const info = await invoke<ImageInfo>("get_image_info", {
                        inputPath: lastImportedPath,
                      });
                      const maxEdge = Math.max(info.width, info.height);
                      setMaxLongEdge(maxEdge);
                    } catch (err) {
                      console.error("获取图片尺寸失败:", err);
                    }
                  }
                  setResizeEnabled(checked);
                }}
              />
              按长边缩放
            </label>
            {resizeEnabled && (
              <>
                <input
                  type="number"
                  className="resize-input"
                  value={maxLongEdge}
                  onChange={(e) => setMaxLongEdge(parseInt(e.target.value) || 0)}
                  min={100}
                  max={8000}
                />
                <span className="hint-text">px</span>
                {[1920, 1280, 800].map((preset) => (
                  <button
                    key={preset}
                    className={`preset-btn ${maxLongEdge === preset ? "active" : ""}`}
                    onClick={() => setMaxLongEdge(preset)}
                  >
                    {preset}
                  </button>
                ))}
              </>
            )}
          </div>
        </>
      )}

      {/* Stats */}
      <div className="stats-row">
        <div className="stat-box">
          <div className="stat-value">{totalCompressed}</div>
          <div className="stat-label">已压缩</div>
        </div>
        <div className="stat-box">
          <div className="stat-value">{formatSize(totalSaved)}</div>
          <div className="stat-label">节省空间</div>
        </div>
        <div className="stat-box">
          <div className="stat-value">{avgRatio.toFixed(1)}%</div>
          <div className="stat-label">平均压缩率</div>
        </div>
        {engine === "tinyPNG" && (
          <div className="stat-box">
            <div className="stat-value">∞</div>
            <div className="stat-label">本地无限</div>
          </div>
        )}
      </div>

      {/* Logs */}
      <div className="log-section">
        <div className="log-header">压缩记录 <span style={{fontSize: '12px', fontWeight: 'normal', color: '#888'}}>(点击复制)</span></div>
        <div className="log-container" style={{ userSelect: 'text' }}>
          {logs.length === 0 ? (
            <div className="log-empty">暂无压缩记录，拖放图片开始压缩</div>
          ) : (
            [...logs].reverse().map((log) => (
              <div key={log.id} className="log-row" onClick={() => copyToClipboard(log)} style={{ cursor: log.status === "success" ? "pointer" : "default" }} title={log.status === "success" ? "点击复制" : ""}>
                <span className="log-file-icon">{getFileIcon(log.extension)}</span>
                <span className="log-filename">{log.filename}</span>
                <span className="log-ext">{log.extension.toUpperCase()}</span>
                {log.status === "waiting" && (
                  <span className="log-status waiting">⏳ 等待中...</span>
                )}
                {log.status === "compressing" && (
                  <span className="log-status processing">🔄 压缩中...</span>
                )}
                {log.status === "success" && (
                  <span className="log-status success">
                    {formatSize(log.originalSize)} → {formatSize(log.compressedSize)} 节省{" "}
                    {((1 - log.compressedSize / log.originalSize) * 100).toFixed(1)}%
                  </span>
                )}
                {log.status === "failed" && (
                  <span className="log-status error">{log.message}</span>
                )}
                <span className="log-time">
                  {log.timestamp.toLocaleTimeString("zh-CN", {
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </span>
              </div>
            ))
          )}
        </div>
      </div>

      <div className="footer-text">
        {overwrite ? "压缩完成后自动覆盖原文件" : "压缩完成后保存为 xxx-compressed.xxx"}
      </div>
    </div>
  );
}
