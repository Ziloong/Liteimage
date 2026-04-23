import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

interface SettingsProps {
  onClose: () => void;
}

export default function Settings({ onClose }: SettingsProps) {
  const [apiKey, setApiKey] = useState("");
  const [showKey, setShowKey] = useState(false);
  const [statusMsg, setStatusMsg] = useState("");
  const [statusType, setStatusType] = useState<"success" | "error" | "">("");
  const [isTesting, setIsTesting] = useState(false);

  useEffect(() => {
    invoke<string | null>("get_stored_api_key").then((key) => {
      if (key) setApiKey(key);
    });
  }, []);

  const handleTest = async () => {
    if (!apiKey) return;
    setIsTesting(true);
    setStatusMsg("");
    setStatusType("");

    try {
      const result = await invoke<{
        is_valid: boolean;
        compression_count: number;
        message: string;
      }>("test_tinypng_api", { apiKey });

      if (result.is_valid) {
        setStatusMsg(result.message);
        setStatusType("success");
      } else {
        setStatusMsg(result.message);
        setStatusType("error");
      }
    } catch (err) {
      setStatusMsg(`❌ ${err}`);
      setStatusType("error");
    } finally {
      setIsTesting(false);
    }
  };

  const handleSave = async () => {
    if (!apiKey) return;
    try {
      await invoke("save_api_key", { apiKey });
      setStatusMsg("✅ 已保存");
      setStatusType("success");
      setTimeout(onClose, 500);
    } catch (err) {
      setStatusMsg(`❌ 保存失败: ${err}`);
      setStatusType("error");
    }
  };

  return (
    <div className="modal-overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal-content">
        <div className="modal-title">API Key 设置</div>
        <div className="modal-subtitle">
          <a href="https://tinypng.com/developers" target="_blank" rel="noopener noreferrer">在 tinypng.com/developers 免费申请</a>
          ，每月可压缩 500 张
        </div>

        <div className="modal-divider" />

        {/* 链接区域 */}
        <div className="modal-links">
          <a href="https://my.feishu.cn/wiki/HsGqwApFRiAkBTkEogicP47VnxF?from=from_copylink" target="_blank" rel="noopener noreferrer">飞书文档</a>
          <span className="modal-link-sep">|</span>
          <a href="https://github.com/Ziloong/Liteimage" target="_blank" rel="noopener noreferrer">Github 仓库</a>
        </div>

        <div className="modal-label">API Key</div>
        <div className="api-input-row">
          <input
            type={showKey ? "text" : "password"}
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder="输入 API Key"
            onKeyDown={(e) => e.key === "Enter" && handleSave()}
          />
          <button className="toggle-visibility" onClick={() => setShowKey(!showKey)}>
            {showKey ? "🙈" : "👁"}
          </button>
        </div>

        {statusMsg && (
          <div className={`modal-status ${statusType}`}>{statusMsg}</div>
        )}

        <div className="modal-actions">
          <button className="btn" onClick={onClose}>
            关闭
          </button>
          <button
            className="btn"
            onClick={handleTest}
            disabled={!apiKey || isTesting}
          >
            {isTesting ? "⏳ 测试中..." : "🔧 测试可用性"}
          </button>
          <button className="btn btn-primary" onClick={handleSave} disabled={!apiKey}>
            保存
          </button>
        </div>
      </div>
    </div>
  );
}
