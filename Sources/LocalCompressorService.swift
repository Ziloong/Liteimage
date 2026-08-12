import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// 本地压缩引擎服务
/// 使用编译好的 pngquant 和 gifski 命令行工具进行本地图片压缩
class LocalCompressorService: @unchecked Sendable {

    /// 当前正在运行的进程（用于停止操作）
    private var currentProcess: Process?
    private let processLock = NSLock()

    /// 取消标志 — 设为 true 后 runTrackedProcess 立刻停止并将后续步骤短路
    /// 注意：读写需通过 markCancelled/resetCancelled/isCancelledFlag 加锁
    private var isCancelled = false

    func markCancelled() {
        processLock.lock()
        isCancelled = true
        processLock.unlock()
    }

    func resetCancelled() {
        processLock.lock()
        isCancelled = false
        processLock.unlock()
    }

    func isCancelledFlag() -> Bool {
        processLock.lock()
        defer { processLock.unlock() }
        return isCancelled
    }

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

    /// 终止当前正在运行的进程
    func terminateCurrentProcess() {
        processLock.lock()
        defer { processLock.unlock() }
        guard let proc = currentProcess, proc.isRunning else { return }
        isCancelled = true
        // SIGKILL 强制秒杀，进程无法忽略
        kill(proc.processIdentifier, SIGKILL)
    }

    /// 安全运行进程（可被 terminateCurrentProcess 中断）
    private func runTrackedProcess(_ process: Process) throws {
        processLock.lock()
        currentProcess = process
        processLock.unlock()
        defer {
            processLock.lock()
            currentProcess = nil
            processLock.unlock()
        }
        try process.run()
        process.waitUntilExit()

        if isCancelledFlag() {
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            throw CompressionError.compressionFailed("进程异常退出 (exit code: \(process.terminationStatus))")
        }
    }

    // 工具路径
    private var pngquantPath: String {
        Bundle.main.resourcePath.map { "\($0)/pngquant" } ?? ""
    }

    private var gifskiPath: String {
        Bundle.main.resourcePath.map { "\($0)/gifski" } ?? ""
    }

    private var oxipngPath: String {
        Bundle.main.resourcePath.map { "\($0)/oxipng" } ?? ""
    }

    private var zopflipngPath: String {
        Bundle.main.resourcePath.map { "\($0)/zopflipng" } ?? ""
    }

    private var posterizePath: String {
        Bundle.main.resourcePath.map { "\($0)/posterize" } ?? ""
    }

    /// 压缩 PNG 图片
    /// - Parameters:
    ///   - inputURL: 输入文件 URL
    ///   - outputURL: 输出文件 URL
    ///   - qualityRange: 质量范围字符串，格式 "min-max"，例如 "85-95"，默认高质量
    ///   - speed: 速度 1-11，默认 4
    /// - Returns: 压缩结果
    func compressPNG(inputURL: URL, outputURL: URL, qualityRange: String = "85-95", speed: Int = 1) async throws -> CompressionResult {
        Logger.shared.log("  🔧 pngquant: \(inputURL.lastPathComponent) quality=\(qualityRange) speed=\(speed)")
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
                    try self.runTrackedProcess(process)

                    // 检查是否成功
                    guard process.terminationStatus == 0 else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                        Logger.shared.log("  ❌ pngquant 失败 (exit=\(process.terminationStatus)): \(errorMessage)")
                        continuation.resume(throwing: CompressionError.compressionFailed(errorMessage))
                        return
                    }

                    // 验证输出文件
                    guard FileManager.default.fileExists(atPath: outputURL.path) else {
                        Logger.shared.log("  ❌ pngquant 输出文件缺失: \(outputURL.path)")
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
                    Logger.shared.log("    pngquant 完成: \(originalSize.formattedSize()) → \(compressedSize.formattedSize())")

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
        Logger.shared.log("  🔧 gifski: \(inputURL.lastPathComponent) quality=\(quality) width=\(width?.description ?? "auto")")
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
                    try self.runTrackedProcess(process)

                    // 检查是否成功
                    guard process.terminationStatus == 0 else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                        Logger.shared.log("  ❌ gifski 失败 (exit=\(process.terminationStatus)): \(errorMessage)")
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
        Logger.shared.log("  📐 缩放: \(inputURL.lastPathComponent) targetLongEdge=\(maxLongEdge)")
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

    /// 将图片转换为 JPEG 格式
    /// - Parameters:
    ///   - inputURL: 输入图片 URL（PNG 等格式）
    ///   - outputURL: 输出 JPEG 文件 URL
    ///   - quality: JPEG 质量 0.0-1.0
    ///   - maxLongEdge: 可选的长边缩放目标（传 nil 则不缩放）
    func convertToJPEG(inputURL: URL, outputURL: URL, quality: CGFloat, maxLongEdge: Int? = nil) async throws {
        Logger.shared.log("  🖼 JPEG转换: \(inputURL.lastPathComponent) quality=\(String(format: "%.0f", quality*100))% longEdge=\(maxLongEdge?.description ?? "none")")
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    continuation.resume(throwing: CompressionError.unsupportedFormat("无法读取图片"))
                    return
                }

                let imageToWrite: CGImage
                if let maxEdge = maxLongEdge, maxEdge > 0 {
                    let srcWidth = cgImage.width
                    let srcHeight = cgImage.height
                    let srcLongEdge = max(srcWidth, srcHeight)
                    if srcLongEdge != maxEdge {
                        let ratio = CGFloat(maxEdge) / CGFloat(srcLongEdge)
                        let dstWidth = Int(CGFloat(srcWidth) * ratio)
                        let dstHeight = Int(CGFloat(srcHeight) * ratio)

                        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                              let context = CGContext(
                                data: nil,
                                width: dstWidth,
                                height: dstHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: cgImage.bitmapInfo.rawValue
                              ),
                              let resized = context.makeImage() else {
                            continuation.resume(throwing: CompressionError.compressionFailed("JPEG 转换缩放失败"))
                            return
                        }
                        context.interpolationQuality = .high
                        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstWidth, height: dstHeight))
                        imageToWrite = resized
                    } else {
                        imageToWrite = cgImage
                    }
                } else {
                    imageToWrite = cgImage
                }

                guard let dest = CGImageDestinationCreateWithURL(
                    outputURL as CFURL,
                    UTType.jpeg.identifier as CFString,
                    1, nil
                ) else {
                    continuation.resume(throwing: CompressionError.compressionFailed("JPEG 输出文件创建失败"))
                    return
                }

                let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
                CGImageDestinationAddImage(dest, imageToWrite, options as CFDictionary)

                if CGImageDestinationFinalize(dest) {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CompressionError.compressionFailed("JPEG 保存失败"))
                }
            }
        }
    }

    /// 将图片转换为 PNG 格式（无损）
    func convertToPNG(inputURL: URL, outputURL: URL) async throws {
        Logger.shared.log("  🖼 PNG转换: \(inputURL.lastPathComponent)")
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    continuation.resume(throwing: CompressionError.unsupportedFormat("无法读取图片"))
                    return
                }

                guard let dest = CGImageDestinationCreateWithURL(
                    outputURL as CFURL,
                    UTType.png.identifier as CFString,
                    1, nil
                ) else {
                    continuation.resume(throwing: CompressionError.compressionFailed("PNG 输出文件创建失败"))
                    return
                }

                CGImageDestinationAddImage(dest, cgImage, nil)
                if CGImageDestinationFinalize(dest) {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CompressionError.compressionFailed("PNG 保存失败"))
                }
            }
        }
    }

    /// 用 oxipng 无损优化 PNG（level 6 最高压缩）
    func optimizeWithOxipng(inputURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: oxipngPath) else {
            Logger.shared.log("  ⚠️ oxipng 未找到，跳过优化")
            return
        }

        Logger.shared.log("  🔧 oxipng(opt=6) 优化: \(inputURL.lastPathComponent)")
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.oxipngPath)
                process.arguments = ["--opt", "6", "--strip", "all", inputURL.path]

                let errorPipe = Pipe()
                process.standardError = errorPipe

                do {
                    try self.runTrackedProcess(process)

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                        Logger.shared.log("  ⚠️ oxipng 警告 (exit=\(process.terminationStatus)): \(errorMessage)")
                    } else {
                        Logger.shared.log("    oxipng 优化完成")
                    }
                    continuation.resume()
                } catch is CancellationError {
                    continuation.resume(throwing: CancellationError())
                } catch {
                    Logger.shared.log("  ⚠️ oxipng 运行失败: \(error.localizedDescription)")
                    continuation.resume()
                }
            }
        }
    }

    /// 用 Posterizer 预量化 PNG（pngquant 前处理，减少颜色数同时保持视觉质量）
    func posterizePNG(inputURL: URL, outputURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: posterizePath) else {
            throw CompressionError.toolNotFound("posterize")
        }

        Logger.shared.log("  🎨 posterize 预量化: \(inputURL.lastPathComponent)")
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.posterizePath)
                process.arguments = ["-Q", "80", "-b", "-d", inputURL.path, outputURL.path]

                let errorPipe = Pipe()
                process.standardError = errorPipe

                do {
                    try self.runTrackedProcess(process)

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
                        Logger.shared.log("  ❌ posterize 失败 (exit=\(process.terminationStatus)): \(errorMessage)")
                        continuation.resume(throwing: CompressionError.compressionFailed(errorMessage))
                    } else {
                        Logger.shared.log("    posterize 完成")
                        continuation.resume()
                    }
                } catch {
                    Logger.shared.log("  ❌ posterize 运行失败: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
}
