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

// MARK: - 视频条目（批量转换用）
struct VideoItem: Identifiable {
    let id = UUID()
    let url: URL
    var duration: Double = 0
    var width: Int = 0
    var height: Int = 0
    var frameRate: Double = 30
    var startTime: Int = 0
    var endTime: Int = 0
    var status: VideoItemStatus = .pending
    var outputURL: URL?
    var errorMessage: String?
}

enum VideoItemStatus {
    case pending
    case converting
    case done
    case failed
}

// MARK: - GIF 转换器 ViewModel
@MainActor
class GIFConverterViewModel: ObservableObject {
    // MARK: - Published 属性（视频转GIF）
    @Published var selectedVideos: [VideoItem] = []
    @Published var selectedQuality: GIFQualityPreset = .medium
    @Published var outputWidth: Int = 480
    @Published var frameRate: Int = 25
    @Published var isConverting: Bool = false
    @Published var totalProgress: Double = 0
    @Published var conversionLogs: [String] = []
    @Published var ffmpegAvailable: Bool = false
    
    // GIF 压缩
    @Published var selectedGIFURLs: [URL] = []
    @Published var isCompressingGIF: Bool = false
    @Published var gifCompressionProgress: Double = 0
    @Published var gifCompressionLogs: [String] = []
    @Published var gifOutputURLs: [URL] = []

    // MARK: - 工具路径
    private var ffmpegPath: String {
        Bundle.main.resourcePath.map { "\($0)/ffmpeg" } ?? ""
    }

    private var gifskiPath: String {
        Bundle.main.resourcePath.map { "\($0)/gifski" } ?? ""
    }

    // MARK: - 检查工具可用性
    func checkFFmpegAvailability() {
        let exists = FileManager.default.fileExists(atPath: ffmpegPath)
        if !exists {
            addLog("⚠️ ffmpeg 未找到，请确保已添加到资源目录")
        }
        ffmpegAvailable = exists
    }

    // MARK: - 批量转换：加载视频
    func loadVideos(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let item = VideoItem(url: url)
            selectedVideos.append(item)
            
            // 异步获取视频信息
            Task {
                await fetchVideoInfo(for: item.id, url: url)
            }
        }
    }

    private func fetchVideoInfo(for id: UUID, url: URL) async {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else { return }

            let size = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let transformedSize = size.applying(transform)
            let width = abs(Int(transformedSize.width))
            let height = abs(Int(transformedSize.height))
            let frameRate = try await videoTrack.load(.nominalFrameRate)

            await MainActor.run {
                if let idx = self.selectedVideos.firstIndex(where: { $0.id == id }) {
                    self.selectedVideos[idx].duration = duration.seconds
                    self.selectedVideos[idx].width = width
                    self.selectedVideos[idx].height = height
                    self.selectedVideos[idx].frameRate = Double(frameRate)
                    self.selectedVideos[idx].endTime = min(Int(5 * Double(frameRate)), Int(duration.seconds * Double(frameRate)))

                    // 自动更新输出设置：宽度取视频宽度，帧率取视频帧率（限制范围内）
                    self.outputWidth = max(160, min(1280, width))
                    self.frameRate = max(5, min(30, Int(frameRate)))
                }
            }
        } catch {
            print("读取视频信息失败: \(error)")
        }
    }

    func removeVideo(_ id: UUID) {
        selectedVideos.removeAll { $0.id == id }
    }

    func clearVideos() {
        selectedVideos.removeAll()
    }

    // MARK: - 批量转换：开始转换
    func startBatchConversion() {
        guard ffmpegAvailable else {
            addLog("❌ ffmpeg 工具不可用")
            return
        }
        guard !selectedVideos.isEmpty else {
            addLog("❌ 请先添加视频文件")
            return
        }

        isConverting = true
        totalProgress = 0

        let total = selectedVideos.count
        var completed = 0

        Task {
            for index in selectedVideos.indices {
                guard !selectedVideos[index].status.isProcessing else { continue }

                await MainActor.run {
                    selectedVideos[index].status = .converting
                }

                do {
                    let outputURL = try await convertSingleVideo(selectedVideos[index])
                    await MainActor.run {
                        selectedVideos[index].status = .done
                        selectedVideos[index].outputURL = outputURL
                    }
                    addLog("✅ [\(index + 1)/\(total)] \(selectedVideos[index].url.lastPathComponent)")
                } catch {
                    await MainActor.run {
                        selectedVideos[index].status = .failed
                        selectedVideos[index].errorMessage = error.localizedDescription
                    }
                    addLog("❌ [\(index + 1)/\(total)] \(selectedVideos[index].url.lastPathComponent): \(error.localizedDescription)")
                }

                completed += 1
                await MainActor.run {
                    self.totalProgress = Double(completed) / Double(total) * 100
                }
            }

            await MainActor.run {
                self.isConverting = false
                self.addLog("🎉 批量转换完成！")
            }
        }
    }

    private func convertSingleVideo(_ item: VideoItem) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gif_conv_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        let framesDir = tempDir.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

        let startSeconds = Double(item.startTime) / item.frameRate
        let duration = Double(item.endTime - item.startTime) / item.frameRate

        // ffmpeg 提取帧
        let ffmpegProcess = Process()
        ffmpegProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
        ffmpegProcess.arguments = [
            "-ss", String(format: "%.2f", startSeconds),
            "-t", String(format: "%.2f", duration),
            "-i", item.url.path,
            "-vf", "scale=\(outputWidth):-1:flags=lanczos,fps=\(frameRate)",
            "-q:v", "1",
            framesDir.appendingPathComponent("frame_%04d.png").path
        ]

        let ffmpegError = Pipe()
        ffmpegProcess.standardError = ffmpegError

        try ffmpegProcess.run()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                ffmpegProcess.waitUntilExit()
                continuation.resume()
            }
        }

        if ffmpegProcess.terminationStatus != 0 {
            let errorData = ffmpegError.fileHandleForReading.readDataToEndOfFile()
            throw NSError(domain: "FFmpeg", code: Int(ffmpegProcess.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "ffmpeg 失败"
            ])
        }

        // gifski 合成
        let frameFiles = try FileManager.default.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.path < $1.path }

        guard !frameFiles.isEmpty else {
            throw NSError(domain: "GIFConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "未提取到帧"])
        }

        let outputGIFURL = tempDir.appendingPathComponent("output.gif")

        let gifskiProcess = Process()
        gifskiProcess.executableURL = URL(fileURLWithPath: gifskiPath)
        gifskiProcess.arguments = [
            "-Q", "\(selectedQuality.quality)",
            "-W", "\(outputWidth)",
            "-r", "\(frameRate)",
            "-o", outputGIFURL.path
        ] + frameFiles.map { $0.path }

        let gifskiError = Pipe()
        gifskiProcess.standardError = gifskiError

        try gifskiProcess.run()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                gifskiProcess.waitUntilExit()
                continuation.resume()
            }
        }

        if gifskiProcess.terminationStatus != 0 {
            let errorData = gifskiError.fileHandleForReading.readDataToEndOfFile()
            throw NSError(domain: "Gifski", code: Int(gifskiProcess.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "gifski 失败"
            ])
        }

        // 移动到视频所在目录
        let videoDir = item.url.deletingLastPathComponent()
        let fileName = item.url.deletingPathExtension().lastPathComponent + ".gif"
        let finalURL = videoDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.copyItem(at: outputGIFURL, to: finalURL)

        return finalURL
    }

    func stopConversion() {
        isConverting = false
        addLog("已停止转换")
    }

    func clearLogs() {
        conversionLogs = []
        gifCompressionLogs = []
    }

    // MARK: - GIF 压缩
    func loadGIFs(_ urls: [URL]) {
        selectedGIFURLs.append(contentsOf: urls)
    }

    func removeGIF(_ url: URL) {
        selectedGIFURLs.removeAll { $0 == url }
    }

    func clearGIFs() {
        selectedGIFURLs.removeAll()
    }

    func startGIFCompression() {
        guard !selectedGIFURLs.isEmpty else {
            addGIFLog("❌ 请先添加 GIF 文件")
            return
        }

        isCompressingGIF = true
        gifCompressionProgress = 0
        gifOutputURLs = []

        let total = selectedGIFURLs.count

        Task {
            for (index, url) in selectedGIFURLs.enumerated() {
                do {
                    let outputURL = try await compressSingleGIF(url)
                    await MainActor.run {
                        gifOutputURLs.append(outputURL)
                    }
                    addGIFLog("✅ [\(index + 1)/\(total)] \(url.lastPathComponent)")
                } catch {
                    addGIFLog("❌ [\(index + 1)/\(total)] \(url.lastPathComponent): \(error.localizedDescription)")
                }

                await MainActor.run {
                    gifCompressionProgress = Double(index + 1) / Double(total) * 100
                }
            }

            await MainActor.run {
                self.isCompressingGIF = false
                self.addGIFLog("🎉 GIF 压缩完成！")
            }
        }
    }

    private func compressSingleGIF(_ inputURL: URL) async throws -> URL {
        let gifskiExec = gifskiPath
        let outputURL = inputURL.deletingLastPathComponent()
            .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + "_compressed.gif")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gifskiExec)
        process.arguments = [
            "-Q", "\(selectedQuality.quality)",
            "-W", "\(outputWidth)",
            "-r", "\(frameRate)",
            "-o", outputURL.path,
            inputURL.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw NSError(domain: "GIFCompressor", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "压缩失败"
            ])
        }

        return outputURL
    }

    func stopGIFCompression() {
        isCompressingGIF = false
        addGIFLog("已停止压缩")
    }

    // MARK: - 日志
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        conversionLogs.append("[\(timestamp)] \(message)")
    }

    private func addGIFLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        gifCompressionLogs.append("[\(timestamp)] \(message)")
    }
}

// MARK: - VideoItemStatus 扩展
extension VideoItemStatus {
    var isProcessing: Bool {
        switch self {
        case .converting: return true
        default: return false
        }
    }
}
