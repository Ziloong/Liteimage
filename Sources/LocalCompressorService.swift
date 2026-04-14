import Foundation

/// 本地压缩引擎服务
/// 使用编译好的 pngquant 和 gifski 命令行工具进行本地图片压缩
class LocalCompressorService: @unchecked Sendable {

    enum CompressionError: LocalizedError {
        case toolNotFound(String)
        case compressionFailed(String)
        case outputFileMissing(String)
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .toolNotFound(let tool):
                return "找不到压缩工具: \(tool)"
            case .compressionFailed(let message):
                return "压缩失败: \(message)"
            case .outputFileMissing(let path):
                return "输出文件不存在: \(path)"
            case .unsupportedFormat(let format):
                return "不支持的格式: \(format)"
            }
        }
    }

    struct CompressionResult {
        let outputURL: URL
        let originalSize: Int64
        let compressedSize: Int64
        let compressionRatio: Double

        var savedBytes: Int64 {
            return originalSize - compressedSize
        }

        var savedPercentage: Double {
            guard originalSize > 0 else { return 0 }
            return Double(savedBytes) / Double(originalSize) * 100
        }
    }

    // 工具路径
    private var pngquantPath: String {
        Bundle.main.resourcePath.map { "\($0)/pngquant" } ?? ""
    }

    private var gifskiPath: String {
        Bundle.main.resourcePath.map { "\($0)/gifski" } ?? ""
    }

    /// 压缩 PNG 图片
    /// - Parameters:
    ///   - inputURL: 输入文件 URL
    ///   - outputURL: 输出文件 URL
    ///   - quality: 质量范围 (0-100)，默认 80
    ///   - speed: 速度 1-11，默认 4
    /// - Returns: 压缩结果
    func compressPNG(inputURL: URL, outputURL: URL, quality: Int = 80, speed: Int = 4) async throws -> CompressionResult {
        // 检查工具是否存在
        guard FileManager.default.fileExists(atPath: pngquantPath) else {
            throw CompressionError.toolNotFound("pngquant")
        }

        let originalSize = try getFileSize(at: inputURL)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.pngquantPath)
                process.arguments = [
                    "--quality=\(quality)",
                    "--speed=\(speed)",
                    "--force",
                    "--output", outputURL.path,
                    inputURL.path
                ]

                // 捕获错误输出
                let errorPipe = Pipe()
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    // 检查是否成功
                    guard process.terminationStatus == 0 else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                        continuation.resume(throwing: CompressionError.compressionFailed(errorMessage))
                        return
                    }

                    // 验证输出文件
                    guard FileManager.default.fileExists(atPath: outputURL.path) else {
                        continuation.resume(throwing: CompressionError.outputFileMissing(outputURL.path))
                        return
                    }

                    let compressedSize = try self.getFileSize(at: outputURL)
                    let result = CompressionResult(
                        outputURL: outputURL,
                        originalSize: originalSize,
                        compressedSize: compressedSize,
                        compressionRatio: Double(compressedSize) / Double(originalSize)
                    )

                    continuation.resume(returning: result)

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 压缩 GIF 图片
    /// - Parameters:
    ///   - inputURL: 输入文件 URL
    ///   - outputURL: 输出文件 URL
    ///   - quality: 质量 1-50，默认 10
    ///   - width: 输出宽度（可选，自动调整）
    /// - Returns: 压缩结果
    func compressGIF(inputURL: URL, outputURL: URL, quality: Int = 10, width: Int? = nil) async throws -> CompressionResult {
        // 检查工具是否存在
        guard FileManager.default.fileExists(atPath: gifskiPath) else {
            throw CompressionError.toolNotFound("gifski")
        }

        let originalSize = try getFileSize(at: inputURL)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.gifskiPath)

                var args = ["--quality", "\(quality)", "-o", outputURL.path, inputURL.path]

                if let width = width, width > 0 {
                    args.insert("--width=\(width)", at: 0)
                    args.insert("\(width)", at: 0)
                }

                process.arguments = args

                // 捕获错误输出
                let errorPipe = Pipe()
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    // 检查是否成功
                    guard process.terminationStatus == 0 else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                        continuation.resume(throwing: CompressionError.compressionFailed(errorMessage))
                        return
                    }

                    // 验证输出文件
                    guard FileManager.default.fileExists(atPath: outputURL.path) else {
                        continuation.resume(throwing: CompressionError.outputFileMissing(outputURL.path))
                        return
                    }

                    let compressedSize = try self.getFileSize(at: outputURL)
                    let result = CompressionResult(
                        outputURL: outputURL,
                        originalSize: originalSize,
                        compressedSize: compressedSize,
                        compressionRatio: Double(compressedSize) / Double(originalSize)
                    )

                    continuation.resume(returning: result)

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 根据文件类型自动选择压缩方法
    func compress(inputURL: URL, outputURL: URL, engine: CompressionEngine, quality: Int = 80) async throws -> CompressionResult {
        let ext = inputURL.pathExtension.lowercased()

        switch ext {
        case "png":
            return try await compressPNG(inputURL: inputURL, outputURL: outputURL, quality: quality)
        case "gif":
            return try await compressGIF(inputURL: inputURL, outputURL: outputURL, quality: min(50, max(1, 100 - quality)))
        default:
            throw CompressionError.unsupportedFormat(ext)
        }
    }

    // MARK: - 辅助方法

    private func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
}
