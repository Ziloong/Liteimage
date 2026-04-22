import Foundation

enum TinyPNGError: Error, LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case networkError
    case serverError
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
        case .invalidResponse:
            return L.invalidResponse
        case .downloadFailed:
            return L.downloadFailed
        }
    }
}

class TinyPNGService {
    private let apiKeyKey = "TinyPNGAPIKey"
    private let baseURL = "https://api.tinify.com/shrink"
    
    var apiKey: String? {
        get {
            UserDefaults.standard.string(forKey: apiKeyKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: apiKeyKey)
        }
    }
    
    func validateAPIKey(_ key: String) async throws -> (isValid: Bool, compressionCount: Int) {
        guard !key.isEmpty else {
            throw TinyPNGError.noAPIKey
        }
        
        let auth = Data("api:\(key)".utf8).base64EncodedString()
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Send a minimal valid image (1x1 transparent PNG)
        let minimalPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")!
        request.httpBody = minimalPNG
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TinyPNGError.invalidResponse
            }
            
            let compressionCount = httpResponse.value(forHTTPHeaderField: "Compression-Count").flatMap { Int($0) } ?? 0
            
            switch httpResponse.statusCode {
            case 200...299:
                return (true, compressionCount)
            case 401:
                throw TinyPNGError.invalidAPIKey
            default:
                throw TinyPNGError.serverError
            }
        } catch let error as TinyPNGError {
            throw error
        } catch {
            throw TinyPNGError.networkError
        }
    }
    
    func compressImage(at inputURL: URL, outputURL: URL? = nil) async throws -> CompressionResult {
        guard let key = apiKey, !key.isEmpty else {
            throw TinyPNGError.noAPIKey
        }
        
        let imageData = try Data(contentsOf: inputURL)
        
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
            throw TinyPNGError.invalidAPIKey
        case 429:
            throw TinyPNGError.serverError
        default:
            throw TinyPNGError.serverError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let downloadURL = output["url"] as? String else {
            throw TinyPNGError.invalidResponse
        }
        
        // Download compressed image
        guard let downloadRequestURL = URL(string: downloadURL) else {
            throw TinyPNGError.invalidResponse
        }
        
        let (compressedData, _) = try await URLSession.shared.data(from: downloadRequestURL)
        
        // Save to output URL (or original if not specified)
        let finalURL = outputURL ?? inputURL
        try compressedData.write(to: finalURL, options: .atomic)
        
        return CompressionResult(
            compressedSize: Int64(compressedData.count),
            compressionCount: compressionCount
        )
    }
}