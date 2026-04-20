use base64::Engine;

pub struct ApiTestResult {
    pub is_valid: bool,
    pub compression_count: u32,
    pub message: String,
}

pub fn test_api(api_key: &str) -> Result<ApiTestResult, String> {
    if api_key.is_empty() {
        return Err("API Key 为空".to_string());
    }

    let auth = base64::engine::general_purpose::STANDARD.encode(format!("api:{}", api_key));

    // Minimal 1x1 transparent PNG
    let minimal_png = base64::engine::general_purpose::STANDARD
        .decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")
        .map_err(|e| e.to_string())?;

    let client = reqwest::blocking::Client::new();
    let response = client
        .post("https://api.tinify.com/shrink")
        .header("Authorization", format!("Basic {}", auth))
        .body(minimal_png)
        .send()
        .map_err(|e| format!("网络请求失败: {}", e))?;

    let compression_count = response
        .headers()
        .get("Compression-Count")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(0);

    match response.status().as_u16() {
        200..=299 => Ok(ApiTestResult {
            is_valid: true,
            compression_count,
            message: format!("API Key 有效! 本月已用 {} 次, 剩余 {} 次", compression_count, 500 - compression_count),
        }),
        401 => Ok(ApiTestResult {
            is_valid: false,
            compression_count,
            message: "API Key 无效".to_string(),
        }),
        status => Err(format!("服务器返回错误: HTTP {}", status)),
    }
}

pub struct CompressResponse {
    pub compressed_size: u64,
}

pub fn compress_image(api_key: &str, input_path: &str) -> Result<CompressResponse, String> {
    let auth = base64::engine::general_purpose::STANDARD.encode(format!("api:{}", api_key));
    let image_data = std::fs::read(input_path).map_err(|e| format!("读取文件失败: {}", e))?;

    let client = reqwest::blocking::Client::new();
    let response = client
        .post("https://api.tinify.com/shrink")
        .header("Authorization", format!("Basic {}", auth))
        .body(image_data)
        .send()
        .map_err(|e| format!("网络请求失败: {}", e))?;

    let status = response.status().as_u16();
    if !(200..=299).contains(&status) {
        return Err(match status {
            401 => "API Key 无效".to_string(),
            429 => "TinyPNG 本月额度已用完".to_string(),
            _ => format!("TinyPNG 服务器错误: HTTP {}", status),
        });
    }

    let body: serde_json::Value = response.json().map_err(|e| format!("解析响应失败: {}", e))?;
    let download_url = body
        .get("output")
        .and_then(|o| o.get("url"))
        .and_then(|u| u.as_str())
        .ok_or("响应中缺少下载链接")?;

    let compressed_data = client
        .get(download_url)
        .send()
        .map_err(|e| format!("下载压缩图片失败: {}", e))?
        .bytes()
        .map_err(|e| format!("读取压缩数据失败: {}", e))?;

    std::fs::write(input_path, &compressed_data).map_err(|e| format!("写入文件失败: {}", e))?;

    Ok(CompressResponse {
        compressed_size: compressed_data.len() as u64,
    })
}
