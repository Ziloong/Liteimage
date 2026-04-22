import Foundation
import Combine

@MainActor
class CompressorViewModel: ObservableObject {
    @Published var logs: [CompressionLog] = []
    @Published var isCompressing = false
    @Published var monthlyUsed: Int?
    @Published var showSettings = false
    @Published var selectedEngine: CompressionEngine = .local  // 默认使用本地引擎
    @Published var shouldOverwrite: Bool = true  // 是否覆盖原文件，默认勾选
    @Published var localQuality: LocalCompressionQuality = .high  // 本地压缩质量，默认高
    @Published var resizeEnabled: Bool = false          // 是否开启尺寸缩放
    @Published var maxLongEdge: Int = 2048              // 最大长边像素

    private let tinyPNGService = TinyPNGService()
    private let localService = LocalCompressorService()
    private var cancellables = Set<AnyCancellable>()

    var totalCompressed: Int {
        logs.filter { $0.isSuccess }.count
    }

    var totalSaved: Int64 {
        logs.filter { $0.isSuccess }.reduce(0) { $0 + $1.savedBytes }
    }

    var averageRatio: Double {
        let successful = logs.filter { $0.isSuccess }
        guard !successful.isEmpty else { return 0 }
        let totalOriginal = successful.reduce(0) { $0 + $1.originalSize }
        let totalSaved = successful.reduce(0) { $0 + $1.savedBytes }
        guard totalOriginal > 0 else { return 0 }
        return Double(totalSaved) / Double(totalOriginal) * 100
    }

    var remainingCount: Int? {
        guard let used = monthlyUsed else { return nil }
        return 500 - used
    }

    // 支持的文件扩展名
    static let supportedExtensions: [String] = ["png", "jpg", "jpeg"]

    func compressFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        // 立即添加等待中的日志
        for url in urls {
            let originalSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let ext = url.pathExtension.lowercased()
            let log = CompressionLog(
                timestamp: Date(),
                filename: url.lastPathComponent,
                originalSize: originalSize,
                compressedSize: 0,
                status: .waiting,
                fileExtension: ext
            )
            logs.append(log)
        }

        // 并行执行压缩
        Task {
            isCompressing = true

            let startIndex = logs.count - urls.count

            await withTaskGroup(of: Void.self) { group in
                for (index, url) in urls.enumerated() {
                    let logIndex = startIndex + index
                    group.addTask {
                        await self.compressSingleFile(url, at: logIndex)
                    }
                }
            }

            isCompressing = false
        }
    }

    private func compressSingleFile(_ url: URL, at index: Int) async {
        // 更新为压缩中状态
        await MainActor.run {
            if index < logs.count {
                logs[index].status = .compressing
            }
        }

        do {
            let result: CompressionResult

            switch selectedEngine {
            case .tinyPNG:
                // 根据设置决定输出路径
                let tinyPNGOutputURL: URL
                if shouldOverwrite {
                    tinyPNGOutputURL = url
                } else {
                    let originalName = url.deletingPathExtension().lastPathComponent
                    tinyPNGOutputURL = url.deletingLastPathComponent()
                        .appendingPathComponent("\(originalName)-compressed.\(url.pathExtension.lowercased())")
                }
                
                result = try await tinyPNGService.compressImage(at: url, outputURL: tinyPNGOutputURL)
                await MainActor.run {
                    monthlyUsed = result.compressionCount
                }

            case .local:
                result = try await compressLocally(at: url)
            }

            await MainActor.run {
                if index < logs.count {
                    logs[index].compressedSize = result.compressedSize
                    let saved = logs[index].savedBytes
                    let ratio = logs[index].ratio
                    logs[index].status = .success(savedBytes: saved, ratio: ratio)
                }
            }

        } catch {
            await MainActor.run {
                if index < logs.count {
                    logs[index].status = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    /// 本地压缩
    private func compressLocally(at url: URL) async throws -> CompressionResult {
        let ext = url.pathExtension.lowercased()

        // 创建临时输出路径
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + "." + ext)

        // 尺寸缩放（按长边，仅本地引擎）
        let processURL: URL
        if resizeEnabled && maxLongEdge > 0 && (ext == "png" || ext == "jpg" || ext == "jpeg") {
            let resizedURL = tempDir.appendingPathComponent(UUID().uuidString + "_resized." + ext)
            let resized = try await localService.resizeIfNeeded(inputURL: url, outputURL: resizedURL, maxLongEdge: maxLongEdge)
            processURL = resized ? resizedURL : url
        } else {
            processURL = url
        }

        switch ext {
        case "png", "jpg", "jpeg":
            _ = try await localService.compressPNG(inputURL: processURL, outputURL: outputURL, qualityRange: localQuality.pngquantRange)
        default:
            throw LocalCompressorService.CompressionError.unsupportedFormat(ext)
        }

        // 清理缩放临时文件
        if resizeEnabled, let resizedURL = resizeEnabled ? tempDir.appendingPathComponent(processURL.lastPathComponent) as URL? : nil,
           resizedURL != url {
            try? FileManager.default.removeItem(at: resizedURL)
        }

        // 根据设置决定最终保存位置
        let finalURL: URL
        if shouldOverwrite {
            // 覆盖原文件
            finalURL = url
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: outputURL, to: finalURL)
        } else {
            // 保存到原文件旁边，文件名后加 "-compressed"
            let originalName = url.deletingPathExtension().lastPathComponent
            finalURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(originalName)-compressed.\(ext)")
            
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: outputURL, to: finalURL)
        }

        // 获取压缩后的文件大小
        let compressedData = try Data(contentsOf: finalURL)

        return CompressionResult(
            compressedSize: Int64(compressedData.count),
            compressionCount: 0  // 本地引擎不消耗 API 次数
        )
    }

    func clearLogs() {
        logs.removeAll()
    }

    func checkAPIKeyOnLaunch() {
        // 不再自动填入默认 API Key
    }
}