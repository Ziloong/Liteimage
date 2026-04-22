//! 内嵌资源模块 - 将所有二进制工具嵌入到 exe 中
//!
//! 资源在程序首次运行时自动提取到临时目录

use std::fs;
use std::io::Write;
use std::path::PathBuf;

/// 获取资源目录（首次调用时自动创建并提取资源）
/// 资源释放到用户数据目录：%LOCALAPPDATA%\LiteImage\resources
pub fn get_temp_resources_dir() -> Result<PathBuf, String> {
    static EXTRACTED: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    
    let dir = EXTRACTED.get_or_init(|| {
        // 获取用户数据目录
        let local_app_data = std::env::var("LOCALAPPDATA")
            .unwrap_or_else(|_| std::env::temp_dir().to_string_lossy().to_string());
        
        let resources_dir = PathBuf::from(local_app_data)
            .join("LiteImage")
            .join("resources");
        
        if let Err(e) = extract_all_resources(&resources_dir) {
            log::error!("提取资源失败: {}", e);
            panic!("无法提取内置资源: {}", e);
        }
        
        resources_dir
    });
    
    Ok(dir.clone())
}

/// 提取所有资源到指定目录
fn extract_all_resources(dir: &PathBuf) -> Result<(), String> {
    // 创建目录
    fs::create_dir_all(dir).map_err(|e| format!("创建资源目录失败: {}", e))?;
    
    log::info!("提取内置资源到: {:?}", dir);
    
    // 提取可执行文件（ffmpeg 是静态编译，不需要 DLL）
    extract_resource(dir, "ffmpeg.exe", include_bytes!("../../resources/ffmpeg.exe"))?;
    extract_resource(dir, "gifski.exe", include_bytes!("../../resources/gifski.exe"))?;
    extract_resource(dir, "pngquant.exe", include_bytes!("../../resources/pngquant.exe"))?;
    
    log::info!("所有资源提取完成");
    Ok(())
}

/// 提取单个资源文件（仅在文件不存在或大小不匹配时提取）
fn extract_resource(dir: &PathBuf, filename: &str, data: &[u8]) -> Result<(), String> {
    let path = dir.join(filename);
    
    // 检查是否已存在且大小匹配（避免重复提取）
    if path.exists() {
        if let Ok(metadata) = fs::metadata(&path) {
            if metadata.len() == data.len() as u64 {
                log::debug!("跳过已存在的资源: {}", filename);
                return Ok(());
            }
        }
    }
    
    // 写入文件
    let mut file = fs::File::create(&path)
        .map_err(|e| format!("创建文件失败 {}: {}", filename, e))?;
    
    file.write_all(data)
        .map_err(|e| format!("写入文件失败 {}: {}", filename, e))?;
    
    log::info!("提取资源: {} ({} bytes)", filename, data.len());
    Ok(())
}
