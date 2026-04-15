import Foundation

// MARK: - 本地化字符串管理
// 自动跟随系统语言，zh-Hans 为默认语言，fallback 到 en

enum L {
    // MARK: - Tab Bar
    static let imageCompress = String(localized: "图片压缩")
    static let videoToGIF = String(localized: "视频转 GIF")

    // MARK: - Engine
    static let tinyPNG = String(localized: "TinyPNG")
    static let localEngine = String(localized: "本地引擎")
    static let tinyPNGDesc = String(localized: "使用云端 TinyPNG API 压缩（需要网络）")
    static let localEngineDesc = String(localized: "使用本地引擎压缩（无需网络）")

    // MARK: - Drop Zone
    static let dropImageTitle = String(localized: "拖放图片到此处")
    static let dropImageSubtitle = String(localized: "或点击选择图片文件")
    static let dropImageHint = String(localized: "支持 PNG / JPG / GIF")
    static let dropVideoTitle = String(localized: "拖放视频文件到这里")
    static let dropVideoSubtitle = String(localized: "或点击选择文件")
    static let dropVideoHint = String(localized: "支持 MP4, MOV, M4V")

    // MARK: - Compression View
    static let overwriteOriginal = String(localized: "覆盖原文件")
    static let resizeByLongEdge = String(localized: "按长边缩放")
    static let resizeHint = String(localized: "超出长边时等比缩放")
    static let overwriteHint = String(localized: "压缩后直接替换原文件")
    static let saveAsHint = String(localized: "压缩后保存为 xxx-compressed.xxx")
    static let overwriteFooter = String(localized: "压缩完成后自动覆盖原文件")
    static let saveAsFooter = String(localized: "压缩完成后保存为 xxx-compressed.xxx")

    // MARK: - Stats
    static let statCompressed = String(localized: "已压缩")
    static let statSaved = String(localized: "节省空间")
    static let statRatio = String(localized: "平均压缩率")
    static let statRemaining = String(localized: "本月剩余")
    static let statUnlimited = String(localized: "本地无限")

    // MARK: - Logs
    static let compressionLog = String(localized: "压缩记录")
    static let noLogHint = String(localized: "暂无压缩记录，拖放图片开始压缩")
    static let waiting = String(localized: "⏳ 等待中...")
    static let compressing = String(localized: "🔄 压缩中...")

    // MARK: - GIF Conversion
    static let quality = String(localized: "质量")
    static let outputSettings = String(localized: "输出设置")
    static let selectVideo = String(localized: "选择视频")
    static let startConversion = String(localized: "开始转换")
    static let log = String(localized: "日志")
    static let waitingForConversion = String(localized: "等待转换...")
    static let conversionDone = String(localized: "转换完成")
    static let showInFinder = String(localized: "在 Finder 中显示")
    static let width = String(localized: "宽度")
    static let framerate = String(localized: "帧率")

    // MARK: - Quality Presets
    static let ultraLowQuality = String(localized: "超低质量")
    static let lowQuality = String(localized: "低质量")
    static let mediumQuality = String(localized: "中等质量")
    static let highQuality = String(localized: "高质量")
    static let ultraLowQualityDesc = String(localized: "最小体积，极低清晰度")
    static let lowQualityDesc = String(localized: "小文件，较低清晰度")
    static let mediumQualityDesc = String(localized: "平衡大小和清晰度")
    static let highQualityDesc = String(localized: "最佳清晰度，较大文件")

    // MARK: - Settings
    static let apiKeySettings = String(localized: "API Key 设置")
    static let apiKeyHint = String(localized: "在 tinypng.com/developers 免费申请，每月可压缩 500 张")
    static let apiKey = String(localized: "API Key")
    static let inputAPIKey = String(localized: "输入 API Key")
    static let close = String(localized: "关闭")
    static let testing = String(localized: "测试中...")
    static let testAPI = String(localized: "测试 API 可用性")
    static let save = String(localized: "保存")
    static let apiKeyValid = String(localized: "✅ API Key 有效！本月已用 %d 次，剩余 %d 次")
    static let saved = String(localized: "✅ 已保存")

    // MARK: - Errors
    static let unknownError = String(localized: "未知错误")
    static let noAPIKey = String(localized: "未设置 API Key")
    static let invalidAPIKey = String(localized: "API Key 无效")
    static let networkError = String(localized: "网络连接失败")
    static let serverError = String(localized: "TinyPNG 服务器错误")
    static let invalidResponse = String(localized: "服务器返回无效响应")
    static let downloadFailed = String(localized: "下载压缩后图片失败")
}
