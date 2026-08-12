import Foundation
import CoreGraphics

// MARK: - 压缩引擎类型
enum CompressionEngine: String, CaseIterable, Identifiable {
    case tinyPNG
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tinyPNG: return L.tinyPNG
        case .local: return L.localEngine
        }
    }

    var description: String {
        switch self {
        case .tinyPNG:
            return L.tinyPNGDesc
        case .local:
            return L.localEngineDesc
        }
    }

    var icon: String {
        switch self {
        case .tinyPNG:
            return "cloud"
        case .local:
            return "cpu"
        }
    }
}

// MARK: - 本地压缩质量
enum LocalCompressionQuality: String, CaseIterable, Identifiable {
    case none
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return L.noCompression
        case .medium: return L.mediumQuality
        case .high:   return L.highQuality
        }
    }

    /// pngquant --quality（.none 不会调用 pngquant）
    var pngquantRange: String {
        switch self {
        case .none:   return "85-95"
        case .medium: return "95-100"
        case .high:   return "95-100"
        }
    }

    /// JPEG 输出质量 (0.0-1.0)，.none 为无损最高质量
    var jpegQuality: CGFloat {
        switch self {
        case .none:   return 1.0
        case .medium: return 0.8
        case .high:   return 0.9
        }
    }
}

// MARK: - 压缩状态
enum CompressionStatus: Equatable {
    case waiting
    case compressing
    case success(savedBytes: Int64, ratio: Double)
    case failed(message: String)
}

// MARK: - 压缩日志
struct CompressionLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let filename: String
    let originalSize: Int64
    var compressedSize: Int64
    var status: CompressionStatus
    let fileExtension: String  // 新增：记录文件扩展名

    var savedBytes: Int64 {
        max(0, originalSize - compressedSize)
    }

    var ratio: Double {
        guard originalSize > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSize) * 100
    }

    var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }

    var formattedCompressedSize: String {
        ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file)
    }

    var formattedSavedBytes: String {
        ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)
    }
    
    var isSuccess: Bool {
        if case .success = status {
            return true
        }
        return false
    }
}

// MARK: - TinyPNG 结果
struct CompressionResult {
    let compressedSize: Int64
    let compressionCount: Int
}

// MARK: - 格式转换选项
enum ConversionFormat: String, CaseIterable, Identifiable {
    case none
    case jpgToPng
    case pngToJpg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:     return L.noConversion
        case .jpgToPng: return L.jpgToPng
        case .pngToJpg: return L.pngToJpg
        }
    }

    /// 根据文件扩展名返回可用的转换选项
    static func availableFormats(for fileExtension: String) -> [ConversionFormat] {
        switch fileExtension.lowercased() {
        case "png":
            return [.none, .pngToJpg]
        case "jpg", "jpeg":
            return [.none, .jpgToPng]
        default:
            return [.none]
        }
    }
}

// MARK: - 图片条目状态
enum ImageItemStatus {
    case pending
    case compressing
    case done
    case failed

    var isProcessing: Bool {
        if case .compressing = self { return true }
        return false
    }
}

// MARK: - 图片条目（用于列表管理）
struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    let originalSize: Int64
    var conversionFormat: ConversionFormat = .none
    var quality: LocalCompressionQuality = .high
    var resizeEnabled: Bool = false
    var maxLongEdge: Int = 2048
    var status: ImageItemStatus = .pending
    var compressedSize: Int64?
    var errorMessage: String?

    var filename: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }

    var savedBytes: Int64 {
        guard let compressed = compressedSize else { return 0 }
        return max(0, originalSize - compressed)
    }

    var ratio: Double {
        guard originalSize > 0, let compressed = compressedSize else { return 0 }
        return Double(originalSize - compressed) / Double(originalSize) * 100
    }
}
