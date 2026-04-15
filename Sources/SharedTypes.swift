import Foundation

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
    case ultraLow
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultraLow: return L.ultraLowQuality
        case .low:      return L.lowQuality
        case .medium:   return L.mediumQuality
        case .high:     return L.highQuality
        }
    }

    /// pngquant --quality=min-max
    var pngquantRange: String {
        switch self {
        case .ultraLow: return "10-20"
        case .low:      return "40-60"
        case .medium:   return "65-80"
        case .high:     return "85-95"
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
