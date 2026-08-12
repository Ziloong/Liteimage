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
    @Published var imageItems: [ImageItem] = []         // 图片列表（本地引擎）

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
        Logger.shared.log("📥 添加 \(urls.count) 个文件到压缩列表")
        addFiles(urls)
    }

    private func compressSingleFile(_ url: URL, at index: Int) async {
        Logger.shared.log("🔄 压缩: \(url.lastPathComponent)")
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
                    Logger.shared.log("✅ 成功: \(url.lastPathComponent) → \(result.compressedSize.formattedSize()) (\(String(format: "%.1f", ratio))%)")
                }
            }

        } catch {
            await MainActor.run {
                if index < logs.count {
                    logs[index].status = .failed(message: error.localizedDescription)
                }
            }
            Logger.shared.log("❌ 失败: \(url.lastPathComponent) - \(error.localizedDescription)")
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

    // MARK: - 列表管理（本地引擎）

    /// 添加文件到压缩列表
    func addFiles(_ urls: [URL]) {
        for url in urls {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            var item = ImageItem(url: url, originalSize: size)
            item.resizeEnabled = resizeEnabled
            item.maxLongEdge = maxLongEdge
            imageItems.append(item)
            Logger.shared.log("  └─ \(url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))")
        }
    }

    /// 移除列表中的图片
    func removeItem(_ id: UUID) {
        imageItems.removeAll { $0.id == id }
    }

    /// 清空列表
    func clearItems() {
        Logger.shared.log("🗑 清空压缩列表")
        imageItems.removeAll()
    }

    /// 停止压缩
    func stopCompression() {
        isCompressing = false
        localService.terminateCurrentProcess()
        // 清除未开始的项和对应日志
        imageItems.removeAll { $0.status == .pending }
        logs.removeAll {
            if case .waiting = $0.status { return true }
            if case .compressing = $0.status { return true }
            return false
        }
    }

    // MARK: - 马上压缩（本地引擎列表模式）

    func startCompression() {
        guard !imageItems.isEmpty, !isCompressing else { return }

        let pendingCount = imageItems.filter { $0.status == .pending }.count
        guard pendingCount > 0 else { return }

        Logger.shared.log("🚀 ===== 开始批量压缩，共 \(pendingCount) 个图片 =====")
        isCompressing = true

        Task {
            for index in imageItems.indices {
                guard isCompressing else { break }

                let item = imageItems[index]
                // 跳过已处理过的
                guard item.status == .pending else { continue }
                Logger.shared.log("🔄 [\(index + 1)/\(imageItems.count)] \(item.filename) (格式:\(item.conversionFormat.displayName) 质量:\(item.quality.displayName))\(item.resizeEnabled ? " 缩放:\(item.maxLongEdge)px" : "")")

                await MainActor.run {
                    imageItems[index].status = .compressing
                }

                // 添加日志
                let log = CompressionLog(
                    timestamp: Date(),
                    filename: item.filename,
                    originalSize: item.originalSize,
                    compressedSize: 0,
                    status: .compressing,
                    fileExtension: item.fileExtension
                )
                await MainActor.run {
                    logs.append(log)
                }
                let logIndex = await MainActor.run { logs.count - 1 }

                do {
                    let result = try await compressImageItem(item)

                    await MainActor.run {
                        imageItems[index].status = .done
                        imageItems[index].compressedSize = result.compressedSize
                        Logger.shared.log("  ✅ 成功: \(item.originalSize.formattedSize()) → \(result.compressedSize.formattedSize()) (\(String(format: "%.1f", item.savedBytes > 0 ? Double(item.savedBytes)/Double(item.originalSize)*100 : 0))%)")
                        if logIndex < logs.count {
                            logs[logIndex].compressedSize = result.compressedSize
                            let saved = logs[logIndex].savedBytes
                            let ratio = logs[logIndex].ratio
                            logs[logIndex].status = .success(savedBytes: saved, ratio: ratio)
                        }
                    }
                } catch {
                    await MainActor.run {
                        imageItems[index].status = .failed
                        imageItems[index].errorMessage = error.localizedDescription
                        Logger.shared.log("  ❌ 失败: \(error.localizedDescription)")
                        if logIndex < logs.count {
                            logs[logIndex].status = .failed(message: error.localizedDescription)
                        }
                    }
                }
            }

            await MainActor.run {
                isCompressing = false
                Logger.shared.log("✅ ===== 批量压缩完成 =====")
            }
        }
    }

    /// 处理单个图片条目（根据质量自动选择 TinyPNG 或本地引擎）
    private func compressImageItem(_ item: ImageItem) async throws -> CompressionResult {
        let quality = item.quality
        let conversion = item.conversionFormat
        let ext = item.fileExtension

        // TinyPNG 条件：高质量 + (不转换 或 PNG→JPG) + 非 JPG 输入 + API Key 存在
        let useTinyPNG = quality == .high
            && (conversion == .none || conversion == .pngToJpg)
            && ext != "jpg" && ext != "jpeg"
            && tinyPNGService.apiKey != nil
            && !(tinyPNGService.apiKey?.isEmpty ?? true)

        if useTinyPNG {
            do {
                return try await compressViaTinyPNG(item)
            } catch {
                Logger.shared.log("  ⚠️ TinyPNG 失败，回退本地引擎: \(error.localizedDescription)")
                return try await compressViaLocal(item)
            }
        } else {
            return try await compressViaLocal(item)
        }
    }

    /// TinyPNG 路径：先压缩 → 后缩放/格式转换
    private func compressViaTinyPNG(_ item: ImageItem) async throws -> CompressionResult {
        let ext = item.fileExtension
        let conversion = item.conversionFormat
        let tempDir = FileManager.default.temporaryDirectory

        // Step 1: TinyPNG 压缩
        Logger.shared.log("  ☁️ TinyPNG: \(item.filename)")
        let compressedURL = tempDir.appendingPathComponent(UUID().uuidString + "." + ext)
        let tinyResult = try await tinyPNGService.compressImage(at: item.url, outputURL: compressedURL)
        await MainActor.run { monthlyUsed = tinyResult.compressionCount }

        // Step 2: 格式转换（如 PNG→JPG，在 TinyPNG 之后）
        let convertedURL: URL
        let outputExt: String
        if conversion == .pngToJpg {
            Logger.shared.log("  🖼 TinyPNG后转JPG")
            convertedURL = tempDir.appendingPathComponent(UUID().uuidString + ".jpg")
            try await localService.convertToJPEG(
                inputURL: compressedURL, outputURL: convertedURL,
                quality: item.quality.jpegQuality)
            outputExt = "jpg"
            try? FileManager.default.removeItem(at: compressedURL)
        } else {
            convertedURL = compressedURL
            outputExt = ext
        }

        // Step 3: 缩放（如需要）
        let finalTempURL: URL
        if item.resizeEnabled && item.maxLongEdge > 0 {
            Logger.shared.log("  📐 TinyPNG后缩放: targetLongEdge=\(item.maxLongEdge)")
            let resizedURL = tempDir.appendingPathComponent(UUID().uuidString + "_resized." + outputExt)
            let didResize = try await localService.resizeIfNeeded(
                inputURL: convertedURL, outputURL: resizedURL, maxLongEdge: item.maxLongEdge)
            finalTempURL = didResize ? resizedURL : convertedURL
        } else {
            finalTempURL = convertedURL
        }

        // Step 4: 移动到最终位置
        let finalURL = resolveOutputURL(for: item, outputExt: outputExt)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: finalTempURL, to: finalURL)

        if finalTempURL != convertedURL { try? FileManager.default.removeItem(at: convertedURL) }

        let compressedData = try Data(contentsOf: finalURL)
        return CompressionResult(compressedSize: Int64(compressedData.count), compressionCount: tinyResult.compressionCount)
    }

    /// 本地引擎路径：先缩放 → 后压缩/转换
    private func compressViaLocal(_ item: ImageItem) async throws -> CompressionResult {
        let ext = item.fileExtension
        let conversion = item.conversionFormat
        let quality = item.quality
        let shouldCompress = quality != .none

        let tempDir = FileManager.default.temporaryDirectory

        // 确定输出格式
        let outputExt: String
        switch conversion {
        case .none:
            outputExt = ext  // 始终保持原格式
        case .jpgToPng:
            outputExt = "png"
        case .pngToJpg:
            outputExt = "jpg"
        }

        let tempOutputURL = tempDir.appendingPathComponent(UUID().uuidString + "." + outputExt)

        // 步骤 1：尺寸缩放
        let processURL: URL
        if item.resizeEnabled && item.maxLongEdge > 0 && (ext == "png" || ext == "jpg" || ext == "jpeg") {
            let resizedURL = tempDir.appendingPathComponent(UUID().uuidString + "_resized." + ext)
            let resized = try await localService.resizeIfNeeded(
                inputURL: item.url, outputURL: resizedURL, maxLongEdge: item.maxLongEdge)
            processURL = resized ? resizedURL : item.url
        } else {
            processURL = item.url
        }

        // 步骤 2：压缩/转换（本地引擎不再使用 pngquant，改为 oxipng 无损优化）
        switch conversion {
        case .none:
            if ext == "png" {
                if shouldCompress {
                    // Posterizer 预量化
                    let posterTemp = tempDir.appendingPathComponent(UUID().uuidString + "_poster.png")
                    try? await localService.posterizePNG(inputURL: processURL, outputURL: posterTemp)
                    let src = FileManager.default.fileExists(atPath: posterTemp.path) ? posterTemp : processURL
                    try FileManager.default.copyItem(at: src, to: tempOutputURL)
                    if src != processURL { try? FileManager.default.removeItem(at: src) }
                } else {
                    try FileManager.default.copyItem(at: processURL, to: tempOutputURL)
                }
            } else {
                if shouldCompress {
                    try await localService.convertToJPEG(
                        inputURL: processURL, outputURL: tempOutputURL,
                        quality: quality.jpegQuality)
                } else {
                    try FileManager.default.copyItem(at: processURL, to: tempOutputURL)
                }
            }

        case .jpgToPng:
            let pngTemp = tempDir.appendingPathComponent(UUID().uuidString + ".png")
            try await localService.convertToPNG(inputURL: processURL, outputURL: pngTemp)
            if shouldCompress {
                let posterTemp = tempDir.appendingPathComponent(UUID().uuidString + "_poster.png")
                try? await localService.posterizePNG(inputURL: pngTemp, outputURL: posterTemp)
                let src = FileManager.default.fileExists(atPath: posterTemp.path) ? posterTemp : pngTemp
                try FileManager.default.copyItem(at: src, to: tempOutputURL)
                if src != pngTemp { try? FileManager.default.removeItem(at: src) }
            } else {
                try FileManager.default.copyItem(at: pngTemp, to: tempOutputURL)
            }
            try? FileManager.default.removeItem(at: pngTemp)

        case .pngToJpg:
            try await localService.convertToJPEG(
                inputURL: processURL, outputURL: tempOutputURL,
                quality: quality.jpegQuality)
        }

        // 清理缩放临时文件
        if item.resizeEnabled, processURL != item.url {
            try? FileManager.default.removeItem(at: processURL)
        }

        // PNG 输出统一用 oxipng 无损优化
        if outputExt == "png" && quality != .none {
            try? await localService.optimizeWithOxipng(inputURL: tempOutputURL)
        }

        // 步骤 3：移动到最终位置
        let finalURL = resolveOutputURL(for: item, outputExt: outputExt)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: tempOutputURL, to: finalURL)

        let compressedData = try Data(contentsOf: finalURL)
        return CompressionResult(compressedSize: Int64(compressedData.count), compressionCount: 0)
    }

    /// 解析最终输出路径
    private func resolveOutputURL(for item: ImageItem, outputExt: String) -> URL {
        if shouldOverwrite {
            if outputExt != item.fileExtension {
                try? FileManager.default.removeItem(at: item.url)
                return item.url.deletingPathExtension().appendingPathExtension(outputExt)
            } else {
                return item.url
            }
        } else {
            let originalName = item.url.deletingPathExtension().lastPathComponent
            return item.url.deletingLastPathComponent()
                .appendingPathComponent("\(originalName)-compressed.\(outputExt)")
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func checkAPIKeyOnLaunch() {
        // 不再自动填入默认 API Key
    }
}