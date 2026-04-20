use std::fs::OpenOptions;
use std::io::Write;
use std::sync::OnceLock;

static LOG_FILE: OnceLock<std::sync::Mutex<std::fs::File>> = OnceLock::new();

fn get_log_file() -> &'static std::sync::Mutex<std::fs::File> {
    LOG_FILE.get_or_init(|| {
        let log_path = std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.join("liteimage-debug.log")))
            .unwrap_or_else(|| std::path::PathBuf::from("liteimage-debug.log"));
        
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .unwrap_or_else(|e| {
                // Fallback: try current dir
                OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open("liteimage-debug.log")
                    .unwrap_or_else(|_| panic!("无法创建日志文件: {}", e))
            });
        
        std::sync::Mutex::new(file)
    })
}

pub fn init_logger() {
    let file = get_log_file();
    if let Ok(mut f) = file.lock() {
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let _ = writeln!(f, "\n=== 轻图启动 [{}] ===", ts);
    }
    log::set_logger(&SimpleLogger).ok();
    log::set_max_level(log::LevelFilter::Info);
}

struct SimpleLogger;

impl log::Log for SimpleLogger {
    fn enabled(&self, _metadata: &log::Metadata) -> bool {
        true
    }

    fn log(&self, record: &log::Record) {
        let file = get_log_file();
        if let Ok(mut f) = file.lock() {
            let ts = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let _ = writeln!(f, "[{}][{}] {}", ts, record.level(), record.args());
        }
    }

    fn flush(&self) {}
}
