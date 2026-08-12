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
                    // 拖放区：无图片时全尺寸，有图片时小号覆盖层
                    Group {
                        if viewModel.imageItems.isEmpty {
                            fullDropZone
                        } else {
                            miniDropOverlay
                        }
                    }
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

                    // 图片列表卡片（含缩放设置）
                    if !viewModel.imageItems.isEmpty {
                        imageListCard
                            .padding(.horizontal)

                        compressNowButton
                            .padding(.horizontal)
                    }
                    
                    // Stats
                    statsView
                        .padding(.horizontal)
                    
                    // Logs
                    logsView
                        .padding(.horizontal)
                    
                    // Footer
                    Text(L.compressionHint)
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

    // MARK: - Drop Zones

    private var fullDropZone: some View {
        DropZoneView(
            isTargeted: $isTargeted,
            onDrop: { urls in viewModel.compressFiles(urls) },
            onTap: { showFilePicker = true },
            acceptedExtensions: ["png", "jpg", "jpeg"]
        )
    }

    private var miniDropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundColor(isTargeted ? .blue : .gray.opacity(0.3))

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.dashed")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                Text(L.addMoreFiles)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 52)
        .background(isTargeted ? Color.blue.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { showFilePicker = true }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await loadFileURL(from: provider) {
                        let ext = url.pathExtension.lowercased()
                        if ["png", "jpg", "jpeg"].contains(ext) {
                            urls.append(url)
                        }
                    }
                }
                await MainActor.run {
                    if !urls.isEmpty { viewModel.compressFiles(urls) }
                }
            }
            return true
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - 图片列表卡片（含缩放设置）

    private var imageListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack {
                Text(L.imageList)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: L.itemCount, viewModel.imageItems.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(L.clearAll) { viewModel.clearItems() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
            }

            Divider()

            // 图片条目
            LazyVStack(spacing: 4) {
                ForEach(viewModel.imageItems) { item in
                    ImageItemRow(
                        item: item,
                        onRemove: { viewModel.removeItem(item.id) },
                        onFormatChange: { format in
                            if let idx = viewModel.imageItems.firstIndex(where: { $0.id == item.id }) {
                                viewModel.imageItems[idx].conversionFormat = format
                            }
                        },
                        onQualityChange: { quality in
                            if let idx = viewModel.imageItems.firstIndex(where: { $0.id == item.id }) {
                                viewModel.imageItems[idx].quality = quality
                            }
                        },
                        onResizeToggle: { enabled in
                            if let idx = viewModel.imageItems.firstIndex(where: { $0.id == item.id }) {
                                viewModel.imageItems[idx].resizeEnabled = enabled
                            }
                        },
                        onMaxLongEdgeChange: { value in
                            if let idx = viewModel.imageItems.firstIndex(where: { $0.id == item.id }) {
                                viewModel.imageItems[idx].maxLongEdge = value
                            }
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 马上压缩按钮

    @ViewBuilder
    private var compressNowButton: some View {
        HStack(spacing: 10) {
            if viewModel.isCompressing {
                ProgressView().controlSize(.small)
                Text(L.converting).font(.caption).foregroundColor(.secondary)
                Button(action: { viewModel.stopCompression() }) {
                    Label(L.stopCompress, systemImage: "stop.fill")
                }
                .buttonStyle(.bordered).tint(.red)
            } else {
                Button(action: { viewModel.startCompression() }) {
                    Label(L.compressNow, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer()
        }
    }

    // MARK: - Stats & Logs

    private var statsView: some View {
        HStack(spacing: 12) {
            StatBox(value: "\(viewModel.totalCompressed)", label: L.statCompressed)
            StatBox(value: viewModel.totalSaved.formattedSize(), label: L.statSaved)
            StatBox(value: String(format: "%.1f%%", viewModel.averageRatio), label: L.statRatio)
            StatBox(
                value: viewModel.remainingCount.map { "\($0)" } ?? "—",
                label: L.statRemaining,
                valueColor: viewModel.remainingCount != nil && viewModel.remainingCount! < 50 ? .red : .primary
            )
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

// MARK: - Image Item Row

struct ImageItemRow: View {
    let item: ImageItem
    let onRemove: () -> Void
    let onFormatChange: (ConversionFormat) -> Void
    let onQualityChange: (LocalCompressionQuality) -> Void
    let onResizeToggle: (Bool) -> Void
    let onMaxLongEdgeChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.filename)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(item.fileExtension.uppercased())
                        .font(.system(size: 8, weight: .medium))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(fileExtColor.opacity(0.15))
                        .foregroundColor(fileExtColor)
                        .cornerRadius(2)
                    Text(item.formattedSize)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                if !item.status.isProcessing {
                    HStack(spacing: 4) {
                        // 缩放 checkbox
                        Toggle("缩放", isOn: Binding(
                            get: { item.resizeEnabled },
                            set: { onResizeToggle($0) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))

                        if item.resizeEnabled {
                            TextField("", value: Binding(
                                get: { item.maxLongEdge },
                                set: { onMaxLongEdgeChange($0) }
                            ), formatter: {
                                let f = NumberFormatter()
                                f.minimum = 100; f.maximum = 8000; f.allowsFloats = false
                                return f
                            }())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 42)
                            .font(.system(size: 10))
                            Text("px").font(.system(size: 9)).foregroundColor(.secondary)

                            ForEach([1920, 1280, 800], id: \.self) { preset in
                                Button("\(preset)") { onMaxLongEdgeChange(preset) }
                                    .font(.system(size: 8))
                                    .padding(.horizontal, 3).padding(.vertical, 1)
                                    .background(item.maxLongEdge == preset ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                    .foregroundColor(item.maxLongEdge == preset ? .white : .secondary)
                                    .cornerRadius(3)
                                    .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        // 格式转换
                        Picker(L.convertFormat, selection: Binding(
                            get: { item.conversionFormat },
                            set: { onFormatChange($0) }
                        )) {
                            ForEach(ConversionFormat.availableFormats(for: item.fileExtension)) { f in
                                Text(f.displayName).tag(f)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden()
                        .frame(width: 100)
                        .font(.system(size: 10))

                        // 质量
                        Picker(L.quality, selection: Binding(
                            get: { item.quality },
                            set: { onQualityChange($0) }
                        )) {
                            ForEach(LocalCompressionQuality.allCases) { q in
                                Text(q.displayName).tag(q)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden()
                        .frame(width: 80)
                        .font(.system(size: 10))

                        // 移除
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary).font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if item.status.isProcessing {
                Spacer()
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
        case .compressing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 13))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 13))
        }
    }

    private var fileExtColor: Color {
        switch item.fileExtension.lowercased() {
        case "png": return .blue
        case "jpg", "jpeg": return .orange
        default: return .secondary
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
