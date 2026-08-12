import Foundation

enum TinyPNGError: Error, LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case networkError
    case serverError
    case quotaExhausted
    case invalidResponse
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return L.noAPIKey
        case .invalidAPIKey:
            return L.invalidAPIKey
        case .networkError:
            return L.networkError
        case .serverError:
            return L.serverError
        case .quotaExhausted:
            return L.quotaExhausted
        case .invalidResponse:
            return L.invalidResponse
        case .downloadFailed:
            return L.downloadFailed
        }
    }
}

class TinyPNGService {
    static let defaultAPIKey = "NYPwQ8Kpjcng9gCSxmhy5hdzBGS7wpzC"
    static let defaultBackupAPIKey = "vbQQ2fGGLVLntTkpNRLCtQbPhFx4Jx8x"

    private let apiKeyKey = "TinyPNGAPIKey"
    private let backupAPIKeyKey = "TinyPNGBackupAPIKey"
    private let baseURL = "https://api.tinify.com/shrink"
    
    var apiKey: String? {
        get { UserDefaults.standard.string(forKey: apiKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }

    var backupAPIKey: String? {
        get { UserDefaults.standard.string(forKey: backupAPIKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: backupAPIKeyKey) }
    }
    
    func validateAPIKey(_ key: String) async throws -> (isValid: Bool, compressionCount: Int) {
        Logger.shared.log("🔑 验证 TinyPNG API Key...")
        guard !key.isEmpty else {
            throw TinyPNGError.noAPIKey
        }
        
        let auth = Data("api:\(key)".utf8).base64EncodedString()
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let minimalPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")!
        request.httpBody = minimalPNG
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TinyPNGError.invalidResponse
            }
            
            let compressionCount = httpResponse.value(forHTTPHeaderField: "Compression-Count").flatMap { Int($0) } ?? 0
            Logger.shared.log("  API Key 有效，本月已用: \(compressionCount)")
            
            switch httpResponse.statusCode {
            case 200...299:
                return (true, compressionCount)
            case 401:
                Logger.shared.log("  ❌ TinyPNG API Key 无效 (401)")
                throw TinyPNGError.invalidAPIKey
            default:
                Logger.shared.log("  ❌ TinyPNG 服务器错误 (status=\(httpResponse.statusCode))")
                throw TinyPNGError.serverError
            }
        } catch let error as TinyPNGError {
            throw error
        } catch {
            throw TinyPNGError.networkError
        }
    }
    
    // MARK: - 压缩（支持主备 Key 自动切换）

    func compressImage(at inputURL: URL, outputURL: URL? = nil) async throws -> CompressionResult {
        guard let primaryKey = apiKey, !primaryKey.isEmpty else {
            throw TinyPNGError.noAPIKey
        }
        
        let imageData = try Data(contentsOf: inputURL)
        
        // 先尝试主 Key
        do {
            return try await compressWithKey(primaryKey, imageData: imageData, outputURL: outputURL ?? inputURL, label: "主Key")
        } catch TinyPNGError.quotaExhausted {
            // 主 Key 额度用完，尝试备用 Key
            guard let backup = backupAPIKey, !backup.isEmpty, backup != primaryKey else {
                throw TinyPNGError.quotaExhausted
            }
            Logger.shared.log("  🔄 主Key 额度耗尽，切换到备用Key")
            return try await compressWithKey(backup, imageData: imageData, outputURL: outputURL ?? inputURL, label: "备用Key")
        }
    }

    /// 用指定 Key 执行压缩
    private func compressWithKey(_ key: String, imageData: Data, outputURL: URL, label: String) async throws -> CompressionResult {
        Logger.shared.log("☁️ TinyPNG(\(label)) 压缩中...")
        
        let auth = Data("api:\(key)".utf8).base64EncodedString()
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TinyPNGError.invalidResponse
        }
        
        let compressionCount = httpResponse.value(forHTTPHeaderField: "Compression-Count").flatMap { Int($0) } ?? 0
        
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            Logger.shared.log("  ❌ TinyPNG(\(label)) API Key 无效 (401)")
            throw TinyPNGError.invalidAPIKey
        case 429:
            Logger.shared.log("  ⚠️ TinyPNG(\(label)) 额度已用完 (429)")
            throw TinyPNGError.quotaExhausted
        default:
            Logger.shared.log("  ❌ TinyPNG(\(label)) 服务器错误 (status=\(httpResponse.statusCode))")
            throw TinyPNGError.serverError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let downloadURL = output["url"] as? String else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            Logger.shared.log("  ❌ TinyPNG(\(label)) 响应解析失败: \(body.prefix(200))")
            throw TinyPNGError.invalidResponse
        }
        
        // Download compressed image
        guard let downloadRequestURL = URL(string: downloadURL) else {
            throw TinyPNGError.invalidResponse
        }
        
        let (compressedData, _) = try await URLSession.shared.data(from: downloadRequestURL)
        
        try compressedData.write(to: outputURL, options: .atomic)
        Logger.shared.log("  TinyPNG(\(label)) 完成: \(Int64(imageData.count).formattedSize()) → \(Int64(compressedData.count).formattedSize())")
        
        return CompressionResult(
            compressedSize: Int64(compressedData.count),
            compressionCount: compressionCount
        )
    }
}