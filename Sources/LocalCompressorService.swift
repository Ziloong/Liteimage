import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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
    ///   - qualityRange: 质量范围字符串，格式 "min-max"，例如 "85-95"，默认高质量
    ///   - speed: 速度 1-11，默认 4
    /// - Returns: 压缩结果
    func compressPNG(inputURL: URL, outputURL: URL, qualityRange: String = "85-95", speed: Int = 4) async throws -> CompressionResult {
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
                    "--quality=\(qualityRange)",
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
            return try await compressPNG(inputURL: inputURL, outputURL: outputURL, qualityRange: "85-95")
        case "gif":
            return try await compressGIF(inputURL: inputURL, outputURL: outputURL, quality: min(50, max(1, 100 - quality)))
        default:
            throw CompressionError.unsupportedFormat(ext)
        }
    }

    // MARK: - 辅助方法

    /// 按长边等比缩放图片（使用 CoreGraphics，支持缩小和放大）
    /// - Parameters:
    ///   - inputURL: 输入文件 URL
    ///   - outputURL: 输出文件 URL
    ///   - maxLongEdge: 目标长边像素
    /// - Returns: true 表示执行了缩放，false 表示图片已经在限制以内无需缩放
    func resizeIfNeeded(inputURL: URL, outputURL: URL, maxLongEdge: Int) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    continuation.resume(throwing: CompressionError.unsupportedFormat("无法读取图片"))
                    return
                }

                let srcWidth = cgImage.width
                let srcHeight = cgImage.height
                let srcLongEdge = max(srcWidth, srcHeight)

                // 如果原图长边已等于目标值，无需缩放
                if srcLongEdge == maxLongEdge {
                    continuation.resume(returning: false)
                    return
                }

                // 计算目标尺寸（等比缩放到 maxLongEdge，支持缩小和放大）
                let ratio = CGFloat(maxLongEdge) / CGFloat(srcLongEdge)
                let dstWidth = Int(CGFloat(srcWidth) * ratio)
                let dstHeight = Int(CGFloat(srcHeight) * ratio)

                // 创建缩放后的图片
                guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
                    continuation.resume(throwing: CompressionError.compressionFailed("无法获取颜色空间"))
                    return
                }

                guard let context = CGContext(
                    data: nil,
                    width: dstWidth,
                    height: dstHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                ) else {
                    continuation.resume(throwing: CompressionError.compressionFailed("缩放上下文创建失败"))
                    return
                }

                context.interpolationQuality = .high
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstWidth, height: dstHeight))

                guard let resizedImage = context.makeImage() else {
                    continuation.resume(throwing: CompressionError.compressionFailed("缩放图片生成失败"))
                    return
                }

                // 保存到输出 URL
                let uti: CFString = inputURL.pathExtension.lowercased() == "png"
                    ? UTType.png.identifier as CFString
                    : UTType.jpeg.identifier as CFString

                guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, uti, 1, nil) else {
                    continuation.resume(throwing: CompressionError.compressionFailed("输出文件创建失败"))
                    return
                }

                CGImageDestinationAddImage(dest, resizedImage, nil)

                if CGImageDestinationFinalize(dest) {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: CompressionError.compressionFailed("缩放图片保存失败"))
                }
            }
        }
    }

    private func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
}
