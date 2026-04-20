import { useState } from "react";
import ImageCompress from "./components/ImageCompress";
import VideoToGif from "./components/VideoToGif";
import Settings from "./components/Settings";
import "./App.css";

function App() {
  const [activeTab, setActiveTab] = useState<"image" | "gif">("image");
  const [showSettings, setShowSettings] = useState(false);

  return (
    <div className="app">
      {/* Tab Bar */}
      <div className="tab-bar">
        <button
          className={`tab-btn ${activeTab === "image" ? "active" : ""}`}
          onClick={() => setActiveTab("image")}
        >
          <span className="tab-icon">🖼</span>
          <span className="tab-text">图片压缩</span>
        </button>
        <button
          className={`tab-btn ${activeTab === "gif" ? "active" : ""}`}
          onClick={() => setActiveTab("gif")}
        >
          <span className="tab-icon">🎬</span>
          <span className="tab-text">视频转 GIF</span>
        </button>
        <div className="tab-spacer" />
        <button className="settings-btn" onClick={() => setShowSettings(true)}>
          ⚙
        </button>
      </div>

      <div className="tab-divider" />

      {/* Content */}
      <div className="tab-content">
        {activeTab === "image" ? <ImageCompress /> : <VideoToGif />}
      </div>

      {/* Settings Modal */}
      {showSettings && <Settings onClose={() => setShowSettings(false)} />}
    </div>
  );
}

export default App;
