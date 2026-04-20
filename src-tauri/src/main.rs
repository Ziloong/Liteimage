#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod logger;
mod embedded_resources;
mod tinypng;

use image::GenericImageView;
use logger::init_logger;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::Manager;

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;



// Config state
struct ApiKeyState(Mutex<Option<String>>);

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct CompressResult {
    pub compressed_size: u64,
    pub original_size: u64,
    pub saved_bytes: u64,
    pub ratio: f64,
    pub output_path: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct VideoInfo {
    pub duration: f64,
    pub width: u32,
    pub height: u32,
    pub fps: f64,
    pub file_size: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct GifResult {
    pub output_path: String,
    pub file_size: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ApiTestResult {
    pub is_valid: bool,
    pub compression_count: u32,
    pub message: String,
}

fn get_config_path() -> PathBuf {
    let app_data = std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(app_data).join("LiteImage").join("config.json")
}

fn load_api_key() -> Option<String> {
    let path = get_config_path();
    if let Ok(content) = fs::read_to_string(&path) {
        if let Ok(config) = serde_json::from_str::<serde_json::Value>(&content) {
            return config.get("api_key").and_then(|v| v.as_str()).map(String::from);
        }
    }
    None
}

fn save_api_key_to_file(key: &str) -> Result<(), String> {
    let path = get_config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let config = serde_json::json!({ "api_key": key });
    let content = serde_json::to_string_pretty(&config).map_err(|e| e.to_string())?;
    fs::write(&path, content).map_err(|e| e.to_string())?;
    Ok(())
}

fn get_resources_dir() -> Result<PathBuf, String> {
    // 使用内嵌资源系统，从临时目录获取资源
    embedded_resources::get_temp_resources_dir()
}

#[tauri::command]
async fn compress_image(
    input_path: String,
    quality_range: String,
    overwrite: bool,
    max_long_edge: u32,
    app: tauri::AppHandle,
) -> Result<CompressResult, String> {
    log::info!("compress_image called: input={}, quality={}, overwrite={}, max_edge={}", input_path, quality_range, overwrite, max_long_edge);
    let result = tokio::task::spawn_blocking(move || {
            let path = PathBuf::from(&input_path);
    let ext = path.extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    
    let original_size = fs::metadata(&path).map_err(|e| e.to_string())?.len();
    let resources_dir = get_resources_dir()?;

    // Determine output path
    let output_path = if overwrite {
        path.clone()
    } else {
        let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("output");
        let parent = path.parent().unwrap_or_else(|| std::path::Path::new("."));
        parent.join(format!("{}-compressed.{}", stem, ext))
    };

    // Step 1: Resize if needed (使用 image crate 原生缩放)
    let process_path = if max_long_edge > 0 && (ext == "png" || ext == "jpg" || ext == "jpeg") {
        let img = image::open(&path).map_err(|e| format!("无法读取图片: {}", e))?;
        let (orig_w, orig_h) = img.dimensions();
        let (new_w, new_h) = if orig_w > orig_h {
            let ratio = max_long_edge as f32 / orig_w as f32;
            (max_long_edge, (orig_h as f32 * ratio) as u32)
        } else {
            let ratio = max_long_edge as f32 / orig_h as f32;
            ((orig_w as f32 * ratio) as u32, max_long_edge)
        };
        let resized = image::imageops::resize(&img.to_rgba8(), new_w, new_h, image::imageops::FilterType::Lanczos3);
        let resized_path = tempfile::tempdir().map_err(|e| e.to_string())?.path().join(format!("resized_{}.{}", std::process::id(), ext));
        resized.save(&resized_path).map_err(|e| format!("缩放保存失败: {}", e))?;
        resized_path.to_path_buf()
    } else {
        path.clone()
    };

    // Step 2: Compress
    match ext.as_str() {
        "png" => {
            let pngquant_path = resources_dir.join("pngquant.exe");
            log::info!("pngquant path: {:?}, exists={}", pngquant_path, pngquant_path.exists());
            if !pngquant_path.exists() {
                return Err("找不到 pngquant.exe".to_string());
            }
            
            let output = std::process::Command::new(&pngquant_path)
                .args([
                    &format!("--quality={}", quality_range),
                    "--speed", "4",
                    "--force",
                    "--output", output_path.to_str().unwrap(),
                    process_path.to_str().unwrap(),
                ])
.creation_flags(CREATE_NO_WINDOW).output()
                .map_err(|e| format!("pngquant 执行失败: {}", e))?;

            log::info!("pngquant stdout: {}", String::from_utf8_lossy(&output.stdout));
            log::info!("pngquant exit code: {:?}", output.status.code());
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                log::error!("pngquant failed: {}", stderr);
                return Err(format!("pngquant 压缩失败: {}", stderr));
            }
        }
        "jpg" | "jpeg" => {
            // 直接用 image crate 读取并重新编码 JPG（Windows 原生，无需外部工具）
            let img = image::open(&process_path)
                .map_err(|e| format!("无法读取图片: {}", e))?;
            
            // quality_range 如 "85-95" 取中间值 90 作为 JPEG 质量 (1-100)
            let jpeg_quality = if let Some((min, max)) = quality_range.split_once('-') {
                let min_q: u8 = min.parse().unwrap_or(85);
                let max_q: u8 = max.parse().unwrap_or(95);
                ((min_q as f32 + max_q as f32) / 2.0) as u8
            } else {
                90
            };

            let mut output_file = std::fs::File::create(&output_path)
                .map_err(|e| format!("无法创建输出文件: {}", e))?;
            let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut output_file, jpeg_quality);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("JPEG 编码失败: {}", e))?;
        }
        "gif" => {
            let gifski_path = resources_dir.join("gifski.exe");
            log::info!("gifski path: {:?}, exists={}", gifski_path, gifski_path.exists());
            if !gifski_path.exists() {
                return Err("找不到 gifski.exe".to_string());
            }

            let output = std::process::Command::new(&gifski_path)
                .args([
                    "--quality", "10",
                    "-o", output_path.to_str().unwrap(),
                    process_path.to_str().unwrap(),
                ])
.creation_flags(CREATE_NO_WINDOW).output()
                .map_err(|e| format!("gifski 执行失败: {}", e))?;

            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                return Err(format!("gifski 压缩失败: {}", stderr));
            }
        }
        _ => return Err(format!("不支持的格式: {}", ext)),
    }

    let compressed_size = fs::metadata(&output_path).map_err(|e| e.to_string())?.len();
    let saved_bytes = original_size.saturating_sub(compressed_size);
    let ratio = if original_size > 0 {
        (saved_bytes as f64 / original_size as f64) * 100.0
    } else {
        0.0
    };

    Ok(CompressResult {
        compressed_size,
        original_size,
        saved_bytes,
        ratio,
        output_path: output_path.to_str().unwrap_or("").to_string(),
    })
    }).await.map_err(|e| format!("Compression task failed: {}", e))??;

    Ok(result)
}

#[tauri::command]
async fn convert_video_to_gif(
    input_path: String,
    quality: u32,
    width: u32,
    fps: u32,
    start_time: f64,
    duration: f64,
) -> Result<GifResult, String> {
    log::info!("convert_video_to_gif called: input={}, quality={}, width={}, fps={}", input_path, quality, width, fps);
    let result = tokio::task::spawn_blocking(move || {
            let resources_dir = get_resources_dir()?;
    let ffmpeg_path = resources_dir.join("ffmpeg.exe");
    let gifski_path = resources_dir.join("gifski.exe");

    let temp_dir = tempfile::tempdir().map_err(|e| e.to_string())?;
    let frames_dir = temp_dir.path().join("frames");
    fs::create_dir_all(&frames_dir).map_err(|e| e.to_string())?;

    // Step 1: Extract frames with ffmpeg
    let frames_pattern = frames_dir.join("frame_%04d.png");
    let output = std::process::Command::new(&ffmpeg_path)
        .args([
            "-y",
            "-ss", &format!("{:.2}", start_time),
            "-t", &format!("{:.2}", duration),
            "-i", &input_path,
            "-vf", &format!("scale={}:-1:flags=lanczos,fps={}", width, fps),
            "-q:v", "1",
            frames_pattern.to_str().unwrap(),
        ])
.creation_flags(CREATE_NO_WINDOW).output()
        .map_err(|e| format!("ffmpeg 执行失败: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("ffmpeg 提取帧失败: {}", stderr));
    }

    // Count frames
    let mut frame_files: Vec<PathBuf> = fs::read_dir(&frames_dir)
        .map_err(|e| e.to_string())?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().map(|ext| ext == "png").unwrap_or(false))
        .collect();
    frame_files.sort();

    if frame_files.is_empty() {
        return Err("未能提取任何帧".to_string());
    }

    // Step 2: Compose GIF with gifski
    let output_gif = temp_dir.path().join("output.gif");
    let mut args: Vec<String> = vec![
        "-Q".to_string(),
        quality.to_string(),
        "-W".to_string(),
        width.to_string(),
        "-r".to_string(),
        fps.to_string(),
        "-o".to_string(),
        output_gif.to_str().unwrap().to_string(),
    ];
    for f in &frame_files {
        args.push(f.to_str().unwrap().to_string());
    }

    let output = std::process::Command::new(&gifski_path)
        .args(&args)
.creation_flags(CREATE_NO_WINDOW).output()
        .map_err(|e| format!("gifski 执行失败: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("gifski 合成失败: {}", stderr));
    }

    // Move to video directory
    let input = PathBuf::from(&input_path);
    let parent = input.parent().unwrap_or_else(|| std::path::Path::new("."));
    let stem = input.file_stem().and_then(|s| s.to_str()).unwrap_or("video");
    let final_path = parent.join(format!("{}_converted.gif", stem));

    if final_path.exists() {
        fs::remove_file(&final_path).map_err(|e| e.to_string())?;
    }
    fs::copy(&output_gif, &final_path).map_err(|e| e.to_string())?;

    let file_size = fs::metadata(&final_path).map_err(|e| e.to_string())?.len();

    Ok(GifResult {
        output_path: final_path.to_str().unwrap_or("").to_string(),
        file_size,
    })
    }).await.map_err(|e| format!("Video conversion task failed: {}", e))??;

    Ok(result)
}

#[tauri::command]
async fn get_video_info(input_path: String) -> Result<VideoInfo, String> {
    log::info!("get_video_info called: input={}", input_path);
    tokio::task::spawn_blocking(move || {
            let resources_dir = get_resources_dir()?;
    let ffprobe_path = resources_dir.join("ffprobe.exe");

    let output = std::process::Command::new(&ffprobe_path)
        .args([
            "-v", "quiet",
            "-print_format", "json",
            "-show_streams", "-show_format",
            &input_path,
        ])
.creation_flags(CREATE_NO_WINDOW).output()
        .map_err(|e| format!("ffprobe 执行失败: {}", e))?;

    if !output.status.success() {
        return Err("ffprobe 执行失败".to_string());
    }

    let json_str = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&json_str).map_err(|e| format!("解析 ffprobe 输出失败: {}", e))?;

    let mut duration = 0.0f64;
    let mut width = 0u32;
    let mut height = 0u32;
    let mut fps = 0.0f64;
    let mut file_size = 0u64;

    if let Some(format) = json.get("format") {
        if let Some(dur) = format.get("duration").and_then(|v| v.as_f64()) {
            duration = dur;
        }
        if let Some(size) = format.get("size").and_then(|v| v.as_str()).and_then(|s| s.parse::<u64>().ok()) {
            file_size = size;
        }
    }

    if let Some(streams) = json.get("streams").and_then(|v| v.as_array()) {
        for stream in streams {
            if stream.get("codec_type").and_then(|v| v.as_str()) == Some("video") {
                if let Some(w) = stream.get("width").and_then(|v| v.as_u64()) {
                    width = w as u32;
                }
                if let Some(h) = stream.get("height").and_then(|v| v.as_u64()) {
                    height = h as u32;
                }
                if let Some(r_frame_rate) = stream.get("r_frame_rate").and_then(|v| v.as_str()) {
                    let parts: Vec<&str> = r_frame_rate.split('/').collect();
                    if parts.len() == 2 {
                        let num: f64 = parts[0].parse().unwrap_or(0.0);
                        let den: f64 = parts[1].parse().unwrap_or(1.0);
                        fps = num / den;
                    }
                }
                break;
            }
        }
    }

    Ok(VideoInfo {
        duration,
        width,
        height,
        fps,
        file_size,
    })
    }).await.map_err(|e| format!("get_video_info task failed: {}", e))?
}

#[tauri::command]
fn get_file_size(path: String) -> Result<u64, String> {
    fs::metadata(&path).map(|m| m.len()).map_err(|e| e.to_string())
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ImageInfo {
    pub width: u32,
    pub height: u32,
    pub size: u64,
}

#[tauri::command]
fn get_image_info(input_path: String) -> Result<ImageInfo, String> {
    let path = PathBuf::from(&input_path);
    let size = fs::metadata(&path).map_err(|e| e.to_string())?.len();
    let img = image::open(&path).map_err(|e| format!("无法读取图片: {}", e))?;
    let (width, height) = img.dimensions();
    Ok(ImageInfo { width, height, size })
}

#[tauri::command]
fn open_file_in_explorer(path: String) -> Result<(), String> {
    let p = PathBuf::from(&path);
    if p.exists() {
        std::process::Command::new("explorer")
            .args(["/select,", p.to_str().unwrap()])
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn get_stored_api_key() -> Result<Option<String>, String> {
    Ok(load_api_key())
}

#[tauri::command]
fn save_api_key(api_key: String) -> Result<(), String> {
    save_api_key_to_file(&api_key)
}

#[tauri::command]
fn test_tinypng_api(api_key: String) -> Result<ApiTestResult, String> {
    let result = tinypng::test_api(&api_key)?;
    Ok(ApiTestResult {
        is_valid: result.is_valid,
        compression_count: result.compression_count,
        message: result.message,
    })
}

#[tauri::command]
fn compress_with_tinypng(input_path: String) -> Result<CompressResult, String> {
    let api_key = load_api_key().ok_or("未设置 API Key")?;
    let path = PathBuf::from(&input_path);
    let original_size = fs::metadata(&path).map_err(|e| e.to_string())?.len();
    
    let _result = tinypng::compress_image(&api_key, &input_path)?;
    
    let compressed_size = fs::metadata(&path).map_err(|e| e.to_string())?.len();
    let saved_bytes = original_size.saturating_sub(compressed_size);
    let ratio = if original_size > 0 {
        (saved_bytes as f64 / original_size as f64) * 100.0
    } else {
        0.0
    };

    Ok(CompressResult {
        compressed_size,
        original_size,
        saved_bytes,
        ratio,
        output_path: input_path,
    })
}

fn dbg_write(msg: &str) {
    // 最原始的文件写入，不依赖任何初始化
    use std::io::Write;
    let log_path = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.join("liteimage-debug.log")))
        .unwrap_or_else(|| std::path::PathBuf::from("liteimage-debug.log"));
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&log_path) {
        let _ = writeln!(f, "[{}] {}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0), msg);
    }
}

fn main() {
    // 1. 最早期的日志，在 logger 初始化之前
    dbg_write("=== LiteImage START ===");
    dbg_write(&format!("exe: {:?}", std::env::current_exe()));

    // 2. 设置 panic hook，捕获所有 panic 写入文件
    std::panic::set_hook(Box::new(|info| {
        dbg_write(&format!("!!! PANIC: {}", info));
        if let Some(loc) = info.location() {
            dbg_write(&format!("    at {}:{}:{}", loc.file(), loc.line(), loc.column()));
        }
    }));

    // 3. 初始化 log crate
    init_logger();
    log::info!("=== LiteImage starting ===");
    log::info!("exe path: {:?}", std::env::current_exe().ok());
    log::info!("current_dir: {:?}", std::env::current_dir().ok());

        // 4. Check resources dir and list contents
    match get_resources_dir() {
        Ok(ref dir) => {
            log::info!("resources dir: {:?}", dir);
            if dir.exists() {
                if let Ok(entries) = std::fs::read_dir(dir) {
                    for entry in entries.flatten() {
                        log::info!("  resource file: {:?}", entry.file_name());
                    }
                }
            } else {
                log::error!("resources dir NOT exists!");
            }
        },
        Err(e) => log::error!("resources dir error: {}", e),
    }

    // 5. 构建并运行 Tauri
    dbg_write("Building Tauri app...");
    let result = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(ApiKeyState(Mutex::new(load_api_key())))
        .invoke_handler(tauri::generate_handler![
            compress_image,
            convert_video_to_gif,
            get_video_info,
            get_file_size,
            get_image_info,
            open_file_in_explorer,
            get_stored_api_key,
            save_api_key,
            test_tinypng_api,
            compress_with_tinypng,
        ])
        .setup(|app| {
            dbg_write("Tauri setup entered");
            if let Some(window) = app.get_webview_window("main") {
                dbg_write("Main window created OK");
            } else {
                dbg_write("ERROR: Main window NOT found!");
            }
            Ok(())
        })
        .run(tauri::generate_context!());

    match result {
        Ok(()) => dbg_write("Tauri app exited normally"),
        Err(e) => dbg_write(&format!("Tauri app ERROR: {}", e)),
    }
}
