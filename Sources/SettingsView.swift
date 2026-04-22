import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusColor: Color = .secondary
    @State private var isTesting: Bool = false
    
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
        .frame(width: 400, height: 360)
        .onAppear {
            apiKey = service.apiKey ?? ""
        }
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
    
    private func save() {
        service.apiKey = apiKey
        statusMessage = L.saved
        statusColor = .green
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}