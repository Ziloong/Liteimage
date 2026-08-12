import Foundation

/// 全局 debug 日志工具
/// 输出到 ~/Library/Logs/LiteImage/ 目录，按日期滚动
final class Logger {
    static let shared = Logger()

    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.liteimage.logger", qos: .utility)
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 是否启用日志（持久化到 UserDefaults）
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "DebugLogEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "DebugLogEnabled")
            if newValue {
                log("━━━━━━━ Debug 日志已启用 ━━━━━━━", force: true)
            }
        }
    }

    private var logDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LiteImage")
    }

    private var todayLogFile: URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        return logDirectory.appendingPathComponent("debug-\(dateStr).log")
    }

    private init() {
        createLogDirectory()
    }

    private func createLogDirectory() {
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    /// 写入日志（仅在 isEnabled 为 true 时生效，force=true 时忽略开关）
    func log(_ message: String, force: Bool = false) {
        guard isEnabled || force else { return }

        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        logQueue.async { [weak self] in
            guard let self = self else { return }
            self.createLogDirectory()

            if let handle = try? FileHandle(forWritingTo: self.todayLogFile) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            } else {
                try? line.data(using: .utf8)?.write(to: self.todayLogFile, options: .atomic)
            }
        }
    }

    /// 获取所有日志文件（按日期降序）
    func logFiles() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.path > $1.path }
    }

    /// 清理超过指定天数的旧日志
    func cleanOldLogs(olderThan days: Int = 7) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        for file in logFiles() {
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let creationDate = attrs[.creationDate] as? Date,
               creationDate < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// 读取最新日志内容（倒序，最新的在前）
    func readLatestLog(maxLines: Int = 1000) -> String {
        guard let latestFile = logFiles().first else { return "暂无日志" }
        guard let content = try? String(contentsOf: latestFile, encoding: .utf8) else {
            return "无法读取日志文件"
        }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let tail = lines.suffix(maxLines)
        return tail.joined(separator: "\n")
    }
}
