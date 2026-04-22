import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = CompressorViewModel()
    @State private var selectedTab: AppTab = .imageCompress
    @State private var showSettings = false
    
    enum AppTab: String, CaseIterable {
        case imageCompress
        case videoToGIF
        
        var displayName: String {
            switch self {
            case .imageCompress: return L.imageCompress
            case .videoToGIF: return L.videoToGIF
            }
        }
        
        var icon: String {
            switch self {
            case .imageCompress: return "photo.stack"
            case .videoToGIF: return "film"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            tabBarView
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            Divider()
            
            // Content - 使用 if-else 替代 TabView
            if selectedTab == .imageCompress {
                ImageCompressView()
                    .environmentObject(viewModel)
            } else {
                GIFConversionView()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
    
    private var tabBarView: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.displayName)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Image Compression View

struct ImageCompressView: View {
    @EnvironmentObject var viewModel: CompressorViewModel
    @State private var isTargeted = false
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Engine Selector
                    engineSelectorView
                        .padding(.horizontal)
                    
                    // Drop Zone
                    DropZoneView(
                        isTargeted: $isTargeted,
                        onDrop: { urls in
                            viewModel.compressFiles(urls)
                        },
                        onTap: {
                            showFilePicker = true
                        },
                        acceptedExtensions: ["png", "jpg", "jpeg"]
                    )
                    .padding(.horizontal)

                    // 覆盖原文件选项
                    HStack(spacing: 8) {
                        Toggle(L.overwriteOriginal, isOn: $viewModel.shouldOverwrite)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        
                        Text(viewModel.shouldOverwrite ? L.overwriteHint : L.saveAsHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal)

                    // 本地引擎质量选项
                    if viewModel.selectedEngine == .local {
                        HStack(spacing: 8) {
                            Text(L.quality)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                ForEach(LocalCompressionQuality.allCases) { q in
                                    Button {
                                        viewModel.localQuality = q
                                    } label: {
                                        Text(q.displayName)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(viewModel.localQuality == q ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                            .foregroundColor(viewModel.localQuality == q ? .white : .primary)
                                            .cornerRadius(5)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal)

                        // 尺寸缩放选项
                        HStack(spacing: 8) {
                            Toggle(L.resizeByLongEdge, isOn: $viewModel.resizeEnabled)
                                .toggleStyle(.checkbox)
                                .font(.caption)

                            if viewModel.resizeEnabled {
                                HStack(spacing: 4) {
                                    TextField("", value: $viewModel.maxLongEdge, formatter: {
                                        let f = NumberFormatter()
                                        f.minimum = 100
                                        f.maximum = 8000
                                        f.allowsFloats = false
                                        return f
                                    }())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                                    .font(.caption)

                                    Text("px")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // 常用预设
                                HStack(spacing: 4) {
                                    ForEach([1920, 1280, 800], id: \.self) { preset in
                                        Button("\(preset)") {
                                            viewModel.maxLongEdge = preset
                                        }
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(viewModel.maxLongEdge == preset ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                        .foregroundColor(viewModel.maxLongEdge == preset ? .white : .secondary)
                                        .cornerRadius(4)
                                        .buttonStyle(.plain)
                                    }
                                }
                            } else {
                                Text(L.resizeHint)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    // Stats
                    statsView
                        .padding(.horizontal)
                    
                    // Logs
                    logsView
                        .padding(.horizontal)
                    
                    // Footer
                    Text(viewModel.shouldOverwrite ? L.overwriteFooter : L.saveAsFooter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.png, .jpeg, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.compressFiles(urls)
            case .failure:
                break
            }
        }
    }
    
    private var engineSelectorView: some View {
        HStack(spacing: 12) {
            ForEach(CompressionEngine.allCases) { engine in
                EngineButton(
                    engine: engine,
                    isSelected: viewModel.selectedEngine == engine,
                    action: { viewModel.selectedEngine = engine }
                )
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var statsView: some View {
        HStack(spacing: 12) {
            StatBox(value: "\(viewModel.totalCompressed)", label: L.statCompressed)
            StatBox(value: viewModel.totalSaved.formattedSize(), label: L.statSaved)
            StatBox(value: String(format: "%.1f%%", viewModel.averageRatio), label: L.statRatio)
            if viewModel.selectedEngine == .tinyPNG {
                StatBox(
                    value: viewModel.remainingCount.map { "\($0)" } ?? "—",
                    label: L.statRemaining,
                    valueColor: viewModel.remainingCount != nil && viewModel.remainingCount! < 50 ? .red : .primary
                )
            } else {
                StatBox(value: "∞", label: L.statUnlimited)
            }
        }
    }
    
    private var logsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.compressionLog)
                .font(.subheadline)
                .fontWeight(.medium)
            
            if viewModel.logs.isEmpty {
                Text(L.noLogHint)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.logs.reversed()) { log in
                        LogRow(log: log)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Supporting Views

struct EngineButton: View {
    let engine: CompressionEngine
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: engine.icon)
                    .font(.system(size: 12))
                Text(engine.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct StatBox: View {
    let value: String
    let label: String
    var valueColor: Color = .primary
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(valueColor)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct LogRow: View {
    let log: CompressionLog
    
    var body: some View {
        HStack {
            fileTypeIcon
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(log.filename)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    
                    Text(log.fileExtension.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(3)
                }
                
                statusText
            }
            
            Spacer()
            
            Text(log.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }
    
    @ViewBuilder
    private var fileTypeIcon: some View {
        switch log.fileExtension.lowercased() {
        case "png":
            Image(systemName: "photo")
                .foregroundColor(.blue)
                .font(.system(size: 14))
        case "jpg", "jpeg":
            Image(systemName: "photo")
                .foregroundColor(.orange)
                .font(.system(size: 14))
        case "gif":
            Image(systemName: "photo.stack")
                .foregroundColor(.purple)
                .font(.system(size: 14))
        default:
            Image(systemName: "doc")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
        }
    }
    
    @ViewBuilder
    private var statusText: some View {
        switch log.status {
        case .waiting:
            Text(L.waiting)
                .font(.system(size: 11))
                .foregroundColor(.orange)
        case .compressing:
            Text(L.compressing)
                .font(.system(size: 11))
                .foregroundColor(.blue)
        case .success:
            Text("\(log.originalSize.formattedSize()) → \(log.compressedSize.formattedSize())  节省 \(String(format: "%.1f", log.ratio))%")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.red)
        }
    }
}

// MARK: - Int64 Extension

extension Int64 {
    func formattedSize() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
