import Foundation
import AVFoundation
import AppKit
import Combine

// MARK: - GIF 质量预设
enum GIFQualityPreset: String, CaseIterable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return L.lowQuality
        case .medium: return L.mediumQuality
        case .high: return L.highQuality
        }
    }

    var description: String {
        switch self {
        case .low: return L.lowQualityDesc
        case .medium: return L.mediumQualityDesc
        case .high: return L.highQualityDesc
        }
    }

    /// gifski quality 参数 (1-100，默认90)
    var quality: Int {
        switch self {
        case .low: return 50
        case .medium: return 70
        case .high: return 90
        }
    }

    var speed: Int {
        switch self {
        case .low: return 50
        case .medium: return 20
        case .high: return 1
        }
    }
}

// MARK: - GIF 转换器 ViewModel
@MainActor
class GIFConverterViewModel: ObservableObject {
    // MARK: - Published 属性
    @Published var selectedVideoURL: URL?
    @Published var selectedQuality: GIFQualityPreset = .medium
    @Published var outputWidth: Int = 480
    @Published var frameRate: Int = 15
    @Published var startTime: Int = 0
    @Published var endTime: Int = 0
    @Published var totalFrames: Int = 0
    @Published var isConverting: Bool = false
    @Published var conversionProgress: Double = 0
    @Published var conversionLogs: [String] = []
    @Published var outputURL: URL?
    @Published var videoDuration: Double = 0
    @Published var videoWidth: Int = 0
    @Published var videoHeight: Int = 0
    @Published var videoFrameRateValue: Double = 30
    @Published var ffmpegAvailable: Bool = false
    @Published var videoFileSize: Int64 = 0

    // MARK: - 工具路径
    private var ffmpegPath: String {
        Bundle.main.resourcePath.map { "\($0)/ffmpeg" } ?? ""
    }

    private var gifskiPath: String {
        Bundle.main.resourcePath.map { "\($0)/gifski" } ?? ""
    }

    // MARK: - 计算属性
    var formattedDuration: String {
        let minutes = Int(videoDuration) / 60
        let seconds = Int(videoDuration) % 60
        let milliseconds = Int((videoDuration.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }

    var videoResolution: String {
        return "\(videoWidth) × \(videoHeight)"
    }

    var videoFrameRate: String {
        return String(format: "%.2f FPS", videoFrameRateValue)
    }

    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: videoFileSize)
    }

    var selectedDurationFormatted: String {
        let frames = max(0, endTime - startTime)
        let seconds = Double(frames) / videoFrameRateValue
        return String(format: "%.1f 秒", seconds)
    }

    // MARK: - 方法

    func checkFFmpegAvailability() {
        let exists = FileManager.default.fileExists(atPath: ffmpegPath)
        if !exists {
            addLog("⚠️ ffmpeg 未找到，请确保已添加到资源目录")
        }
        ffmpegAvailable = exists
    }

    func loadVideo(url: URL) {
        // 确保可以访问文件
        guard url.startAccessingSecurityScopedResource() else {
            addLog("无法访问文件: \(url.lastPathComponent)")
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

        selectedVideoURL = url
        outputURL = nil
        conversionLogs = []

        // 获取文件大小
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            videoFileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            videoFileSize = 0
        }

        // 使用 AVAsset 获取视频信息
        let asset = AVAsset(url: url)

        Task {
            do {
                let duration = try await asset.load(.duration)
                videoDuration = duration.seconds

                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else {
                    addLog("无法读取视频轨道")
                    return
                }

                let size = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)

                // 应用变换获取正确尺寸
                let transformedSize = size.applying(transform)
                videoWidth = abs(Int(transformedSize.width))
                videoHeight = abs(Int(transformedSize.height))

                // 估算帧率
                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                videoFrameRateValue = Double(nominalFrameRate)

                // 设置时间范围
                totalFrames = Int(videoDuration * videoFrameRateValue)
                startTime = 0
                endTime = min(totalFrames, Int(5 * videoFrameRateValue)) // 默认 5 秒

                // 自动调整输出宽度
                if videoWidth > 0 {
                    outputWidth = min(videoWidth, 640) // 最大 640px
                }

                addLog("✅ 加载视频成功: \(url.lastPathComponent)")
                addLog("   分辨率: \(videoWidth)×\(videoHeight)")
                addLog("   时长: \(formattedDuration)")

            } catch {
                addLog("❌ 读取视频信息失败: \(error.localizedDescription)")
            }
        }
    }

    func frameToTimeString(_ frame: Int) -> String {
        let seconds = Double(frame) / videoFrameRateValue
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, secs, ms)
    }

    func startConversion() {
        guard let inputURL = selectedVideoURL else {
            addLog("❌ 请先选择视频文件")
            return
        }

        guard ffmpegAvailable else {
            addLog("❌ ffmpeg 工具不可用")
            return
        }

        guard endTime > startTime else {
            addLog("❌ 结束时间必须大于开始时间")
            return
        }

        isConverting = true
        conversionProgress = 0
        outputURL = nil

        // 创建临时目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gif_conversion_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            addLog("❌ 无法创建临时目录")
            isConverting = false
            return
        }

        // 计算时间参数
        let startSeconds = Double(startTime) / videoFrameRateValue
        let duration = Double(endTime - startTime) / videoFrameRateValue

        // 帧提取目录
        let framesDir = tempDir.appendingPathComponent("frames")
        do {
            try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        } catch {
            addLog("❌ 无法创建帧目录")
            isConverting = false
            return
        }

        addLog("开始转换...")
        addLog("   质量: \(selectedQuality.title) (quality=\(selectedQuality.quality))")
        addLog("   宽度: \(outputWidth)px")
        addLog("   帧率: \(frameRate) FPS")
        addLog("   时长: \(String(format: "%.1f", duration))秒")

        Task {
            do {
                // 步骤 1: 使用 ffmpeg 提取帧为 PNG
                addLog("步骤 1/2: 提取视频帧为 PNG...")

                let ffmpegProcess = Process()
                ffmpegProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
                ffmpegProcess.arguments = [
                    "-ss", String(format: "%.2f", startSeconds),
                    "-t", String(format: "%.2f", duration),
                    "-i", inputURL.path,
                    "-vf", "scale=\(outputWidth):-1:flags=lanczos,fps=\(frameRate)",
                    "-q:v", "1",
                    framesDir.appendingPathComponent("frame_%04d.png").path
                ]

                let ffmpegOutput = Pipe()
                let ffmpegError = Pipe()
                ffmpegProcess.standardOutput = ffmpegOutput
                ffmpegProcess.standardError = ffmpegError

                try ffmpegProcess.run()
                let ffmpegResult = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                    DispatchQueue.global().async {
                        ffmpegProcess.waitUntilExit()
                        continuation.resume(returning: Int(ffmpegProcess.terminationStatus))
                    }
                }

                if ffmpegResult != 0 {
                    let errorData = ffmpegError.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                    throw NSError(domain: "FFmpeg", code: Int(ffmpegProcess.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: "ffmpeg 提取帧失败: \(errorMessage)"
                    ])
                }

                // 获取提取的帧数
                let frameFiles = try FileManager.default.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension.lowercased() == "png" }
                    .sorted { $0.path < $1.path }

                if frameFiles.isEmpty {
                    throw NSError(domain: "GIFConverter", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "未能提取任何帧"
                    ])
                }

                addLog("✅ 提取了 \(frameFiles.count) 帧")

                // 步骤 2: 使用 gifski 从 PNG 文件序列生成 GIF
                addLog("步骤 2/2: 使用 gifski 合成 GIF...")

                let outputGIFURL = tempDir.appendingPathComponent("output.gif")

                let gifskiProcess = Process()
                gifskiProcess.executableURL = URL(fileURLWithPath: gifskiPath)
                
                // gifski 参数格式 (来自 gifski --help):
                // -Q/--quality <1-100>  质量参数 (默认90)
                // -W/--width <px>       最大宽度
                // -r/--fps <num>       帧率
                // --fast               50%更快，质量差10%
                // --extra              50%更慢，质量好1%
                // -o/--output <path>   输出文件
                // [png files...]       PNG 输入文件
                
                var arguments: [String] = []
                arguments.append(contentsOf: ["-Q", "\(selectedQuality.quality)"])
                if outputWidth > 0 {
                    arguments.append(contentsOf: ["-W", "\(outputWidth)"])
                }
                arguments.append(contentsOf: ["-r", "\(frameRate)"])
                arguments.append(contentsOf: ["-o", outputGIFURL.path])
                arguments.append(contentsOf: frameFiles.map { $0.path })
                
                gifskiProcess.arguments = arguments

                let gifskiOutput = Pipe()
                let gifskiError = Pipe()
                gifskiProcess.standardOutput = gifskiOutput
                gifskiProcess.standardError = gifskiError

                try gifskiProcess.run()
                
                let gifskiResult = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                    DispatchQueue.global().async {
                        gifskiProcess.waitUntilExit()
                        continuation.resume(returning: Int(gifskiProcess.terminationStatus))
                    }
                }

                if gifskiResult != 0 {
                    let errorData = gifskiError.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                    throw NSError(domain: "Gifski", code: Int(gifskiProcess.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: "gifski 合成失败: \(errorMessage)"
                    ])
                }

                // 移动到视频文件所在目录
                let videoDir = inputURL.deletingLastPathComponent()
                let fileName = inputURL.deletingPathExtension().lastPathComponent + "_converted.gif"
                let finalURL = videoDir.appendingPathComponent(fileName)

                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }

                try FileManager.default.moveItem(at: outputGIFURL, to: finalURL)

                // 清理临时文件
                try? FileManager.default.removeItem(at: tempDir)

                // 完成
                let fileSize = try FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64 ?? 0
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file

                await MainActor.run {
                    self.outputURL = finalURL
                    self.conversionProgress = 100
                    self.isConverting = false
                    self.addLog("✅ 转换成功!")
                    self.addLog("   输出: \(finalURL.lastPathComponent)")
                    self.addLog("   大小: \(formatter.string(fromByteCount: fileSize))")
                }

            } catch {
                await MainActor.run {
                    self.isConverting = false
                    self.addLog("❌ 转换失败: \(error.localizedDescription)")
                }

                // 清理
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
    }

    func stopConversion() {
        isConverting = false
        addLog("已停止转换")
    }

    func clearLogs() {
        conversionLogs = []
    }

    func generateThumbnail() {
        guard let url = selectedVideoURL else { return }
        addLog("生成缩略图...")

        Task {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            do {
                let time = CMTime(seconds: 1, preferredTimescale: 600)
                _ = try await generator.image(at: time).image

                addLog("✅ 缩略图已生成")
            } catch {
                addLog("⚠️ 缩略图生成失败: \(error.localizedDescription)")
            }
        }
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        conversionLogs.append("[\(timestamp)] \(message)")
    }
}
