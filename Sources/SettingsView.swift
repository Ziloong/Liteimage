import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusColor: Color = .secondary
    @State private var isTesting: Bool = false
    @State private var isTestingBackup: Bool = false
    @State private var isDebugEnabled: Bool = false
    @State private var showLogViewer: Bool = false
    @State private var logContent: String = ""
    @State private var backupAPIKey: String = ""
    @State private var showBackupAPIKey: Bool = false
    
    private let service = TinyPNGService()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text(L.apiKeySettings)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(L.apiKeyHint)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: {
                    if let url = URL(string: "https://tinypng.com/developers") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                        Text(L.getFreeAPIKey)
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            
            Divider()
                .padding(.horizontal)
            
            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text(L.apiKey)
                    .font(.headline)
                
                HStack {
                    if showAPIKey {
                        TextField(L.inputAPIKey, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(L.inputAPIKey, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)

            // 备用 API Key 输入
            VStack(alignment: .leading, spacing: 8) {
                Text(L.backupAPIKeyLabel)
                    .font(.headline)
                Text(L.backupAPIKeyHint)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if showBackupAPIKey {
                        TextField(L.inputAPIKey, text: $backupAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(L.inputAPIKey, text: $backupAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { showBackupAPIKey.toggle() }) {
                        Image(systemName: showBackupAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)

            // 还原默认 Key
            HStack {
                Button(action: restoreDefaults) {
                    Label(L.restoreAPIKeys, systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.horizontal)

            // Status
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text(L.close)
                }
                .buttonStyle(.bordered)

                Button(action: testBackupAPI) {
                    HStack {
                        if isTestingBackup {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text(isTestingBackup ? L.testing : L.testBackupAPI)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(backupAPIKey.isEmpty || isTesting || isTestingBackup)
                
                Button(action: testAPI) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text(isTesting ? L.testing : L.testAPI)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(apiKey.isEmpty || isTesting)
                
                Button(action: save) {
                    Text(L.save)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty)
            }
            .padding(.bottom, 20)

            // Debug 日志开关
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.debugLog)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(L.debugLogHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $isDebugEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: isDebugEnabled) { newValue in
                            Logger.shared.isEnabled = newValue
                        }
                }
            }
            .padding(.horizontal)

            // 查看日志按钮
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(spacing: 12) {
                    Button(action: {
                        logContent = Logger.shared.readLatestLog()
                        showLogViewer = true
                    }) {
                        Label(L.viewLog, systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        let logDir = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Library/Logs/LiteImage")
                        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(logDir)
                    }) {
                        Label(L.openLogDir, systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
            .padding(.horizontal)

            // 底部链接
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(L.feishuDocLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: {
                        if let url = URL(string: "https://my.feishu.cn/wiki/HsGqwApFRiAkBTkEogicP47VnxF") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("my.feishu.cn/wiki/HsGqwApFRiAkBTkEogicP47VnxF")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 4) {
                    Text(L.repoLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: {
                        if let url = URL(string: "https://github.com/Ziloong/Liteimage") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("github.com/Ziloong/Liteimage")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 400, height: 560)
        .onAppear {
            apiKey = service.apiKey ?? TinyPNGService.defaultAPIKey
            backupAPIKey = service.backupAPIKey ?? TinyPNGService.defaultBackupAPIKey
            isDebugEnabled = Logger.shared.isEnabled
        }
        .sheet(isPresented: $showLogViewer) {
            LogViewerSheet(logContent: logContent)
        }
    }
    
    private func restoreDefaults() {
        apiKey = TinyPNGService.defaultAPIKey
        backupAPIKey = TinyPNGService.defaultBackupAPIKey
        service.apiKey = TinyPNGService.defaultAPIKey
        service.backupAPIKey = TinyPNGService.defaultBackupAPIKey
        statusMessage = L.restored
        statusColor = .green
    }

    private func testAPI() {
        isTesting = true
        statusMessage = ""
        
        Task {
            do {
                let result = try await service.validateAPIKey(apiKey)
                if result.isValid {
                    statusMessage = String(format: L.apiKeyValid, result.compressionCount, 500 - result.compressionCount)
                    statusColor = .green
                }
            } catch {
                statusMessage = "❌ \(error.localizedDescription)"
                statusColor = .red
            }
            isTesting = false
        }
    }
    
    private func testBackupAPI() {
        isTestingBackup = true
        statusMessage = ""
        
        Task {
            do {
                let result = try await service.validateAPIKey(backupAPIKey)
                if result.isValid {
                    statusMessage = String(format: L.apiKeyValid, result.compressionCount, 500 - result.compressionCount)
                    statusColor = .green
                }
            } catch {
                statusMessage = "❌ \(error.localizedDescription)"
                statusColor = .red
            }
            isTestingBackup = false
        }
    }

    private func save() {
        service.apiKey = apiKey
        service.backupAPIKey = backupAPIKey
        statusMessage = L.saved
        statusColor = .green
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}

// MARK: - 日志查看器 Sheet

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let logContent: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.viewLog)
                    .font(.headline)
                Spacer()
                Button(L.close) { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                Text(logContent)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 700, height: 500)
    }
}