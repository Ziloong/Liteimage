import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct GIFConversionView: View {
    @StateObject private var viewModel = GIFConverterViewModel()
    @State private var isShowingFilePicker = false
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // 拖放区域（与图片压缩一致的大拖放框）
                    mainDropZone
                        .padding(.horizontal)

                    // 文件列表
                    fileListSection
                        .padding(.horizontal)

                    // 设置选项（质量 + 宽度 + 帧率）— 简单横向排列
                    settingsRow
                        .padding(.horizontal)

                    // 操作按钮
                    actionButtonSection
                        .padding(.horizontal)

                    // 统计
                    statsSection
                        .padding(.horizontal)

                    // 日志卡片
                    logCardSection
                        .padding(.horizontal)

                    // 底部提示
                    Text(L.gifFooterHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 12)
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.movie, .video, UTType(filenameExtension: "mov")!, UTType(filenameExtension: "mp4")!, UTType(filenameExtension: "m4v")!, UTType(filenameExtension: "gif")!].compactMap { $0 },
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                handleImportedFiles(urls)
            case .failure(let error):
                print("选择文件失败: \(error)")
            }
        }
        .onAppear {
            viewModel.checkFFmpegAvailability()
        }
    }

    // MARK: - 主拖放区（复用 DropZoneView 风格）
    @ViewBuilder
    private var mainDropZone: some View {
        let hasFiles = !viewModel.selectedVideos.isEmpty || !viewModel.selectedGIFURLs.isEmpty

        if hasFiles {
            // 有文件时显示小号覆盖层
            miniDropOverlay
        } else {
            // 无文件时显示完整大拖放框
            fullDropZone
        }
    }

    @ViewBuilder
    private var fullDropZone: some View {
        ZStack {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(isTargeted ? .orange : .secondary)

                Text(L.dropUnifiedTitle)
                    .font(.headline)
                    .foregroundColor(isTargeted ? .primary : .secondary)

                Text(L.dropUnifiedSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(L.dropUnifiedHint)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isTargeted ? Color.orange : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                            )
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture { isShowingFilePicker = true }
            .onDrop(of: [.movie, .video, .fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
    }

    @ViewBuilder
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
        .onTapGesture { isShowingFilePicker = true }
        .onDrop(of: [.movie, .video, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - 文件列表
    @ViewBuilder
    private var fileListSection: some View {
        let hasVideos = !viewModel.selectedVideos.isEmpty
        let hasGIFs = !viewModel.selectedGIFURLs.isEmpty

        if hasVideos || hasGIFs {
            VStack(spacing: 8) {
                // 视频列表
                if hasVideos {
                    ForEach(viewModel.selectedVideos) { video in
                        VideoItemRow(video: video) {
                            viewModel.removeVideo(video.id)
                        }
                    }
                }

                // GIF 列表
                if hasGIFs {
                    ForEach(viewModel.selectedGIFURLs, id: \.self) { url in
                        GIFItemRow(url: url) {
                            viewModel.removeGIF(url)
                        }
                    }
                }

                // 底部统计 & 清空
                HStack {
                    let parts: [String] = [
                        viewModel.selectedVideos.isEmpty ? nil : "\(viewModel.selectedVideos.count) 个视频",
                        viewModel.selectedGIFURLs.isEmpty ? nil : "\(viewModel.selectedGIFURLs.count) 个 GIF"
                    ].compactMap { $0 }

                    Text(parts.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(L.clearAll) {
                        viewModel.clearVideos()
                        viewModel.clearGIFs()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - 设置行（简单横向，类似图片压缩的质量选项）
    @ViewBuilder
    private var settingsRow: some View {
        // 质量选择
        HStack(spacing: 8) {
            Text(L.quality)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(GIFQualityPreset.allCases, id: \.self) { preset in
                    Button(preset.title) {
                        viewModel.selectedQuality = preset
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(viewModel.selectedQuality == preset ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .foregroundColor(viewModel.selectedQuality == preset ? .white : .primary)
                    .cornerRadius(5)
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }

        // 宽度 + 帧率
        HStack(spacing: 16) {
            // 宽度
            HStack(spacing: 6) {
                Text(L.width).font(.caption).foregroundColor(.secondary)
                Slider(value: Binding(
                    get: { Double(viewModel.outputWidth) },
                    set: { viewModel.outputWidth = Int($0) }
                ), in: 160...1280, step: 40)
                    .controlSize(.mini)
                    .frame(width: 120)
                Text("\(viewModel.outputWidth) px")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
            }

            Divider().frame(height: 16)

            // 帧率
            HStack(spacing: 6) {
                Text(L.framerate).font(.caption).foregroundColor(.secondary)
                Slider(value: Binding(
                    get: { Double(viewModel.frameRate) },
                    set: { viewModel.frameRate = Int($0) }
                ), in: 5...30, step: 5)
                    .controlSize(.mini)
                    .frame(width: 100)
                Text("\(viewModel.frameRate) FPS")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
            }

            Spacer()
        }
    }

    // MARK: - 操作按钮
    @ViewBuilder
    private var actionButtonSection: some View {
        let hasVideos = !viewModel.selectedVideos.isEmpty
        let hasGIFs = !viewModel.selectedGIFURLs.isEmpty
        let isProcessing = viewModel.isConverting || viewModel.isCompressingGIF

        HStack(spacing: 10) {
            if !isProcessing && (hasVideos || hasGIFs) {
                if hasVideos {
                    Button(action: { viewModel.startBatchConversion() }) {
                        Label(L.batchConversion, systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent)
                }

                if hasGIFs {
                    Button(action: { viewModel.startGIFCompression() }) {
                        Label(L.compressGIF, systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent)
                }
            } else if isProcessing {
                if viewModel.isConverting {
                    ProgressView()
                        .controlSize(.small)
                    Text("转换中...")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { viewModel.stopConversion() }) {
                        Label(L.stopConversion, systemImage: "stop.fill")
                    }.buttonStyle(.bordered).tint(.red)
                } else if viewModel.isCompressingGIF {
                    ProgressView()
                        .controlSize(.small)
                    Text("压缩中...")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { viewModel.stopGIFCompression() }) {
                        Label(L.stopGIFCompression, systemImage: "stop.fill")
                    }.buttonStyle(.bordered).tint(.red)
                }
            }

            Spacer()
        }
    }

    // MARK: - 统计
    @ViewBuilder
    private var statsSection: some View {
        let doneCount = viewModel.selectedVideos.filter { $0.status == .done }.count
        let failedCount = viewModel.selectedVideos.filter { $0.status == .failed }.count
        let gifDoneCount = viewModel.gifOutputURLs.count

        if doneCount > 0 || gifDoneCount > 0 {
            HStack(spacing: 12) {
                StatBox(
                    value: "\(doneCount + gifDoneCount)",
                    label: L.statCompleted,
                    valueColor: .green
                )
                if failedCount > 0 {
                    StatBox(
                        value: "\(failedCount)",
                        label: L.statFailed,
                        valueColor: .red
                    )
                }
                Spacer()

                // 在 Finder 中显示按钮
                Button(action: { showOutputInFinder() }) {
                    Label(L.showInFinder, systemImage: "folder")
                }.buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 日志卡片（与图片压缩一致的风格）
    @ViewBuilder
    private var logCardSection: some View {
        let allLogs = viewModel.conversionLogs + viewModel.gifCompressionLogs

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.log)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !allLogs.isEmpty {
                    Button("清空") {
                        viewModel.clearLogs()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            if allLogs.isEmpty {
                Text(L.waitingForConversion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(allLogs.indices, id: \.self) { index in
                            Text(allLogs[index])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor).opacity(0.4))
                                .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 拖放处理
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in providers {
                let typeIdentifiers = ["public.movie", "public.video", "com.apple.quicktime-movie", "public.mpeg-4", "com.apple.m4v-video"]
                var loaded = false

                for type in typeIdentifiers {
                    if provider.hasItemConformingToTypeIdentifier(type) {
                        if let url = await loadItemAsURL(from: provider, type: type) {
                            urls.append(url)
                            loaded = true
                            break
                        }
                    }
                }

                if !loaded {
                    if let url = await loadFileURL(from: provider) {
                        urls.append(url)
                    }
                }
            }

            await MainActor.run {
                if !urls.isEmpty { handleDroppedFiles(urls) }
            }
        }

        return true
    }

    private func handleDroppedFiles(_ urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "gif" {
                viewModel.loadGIFs([url])
            } else {
                viewModel.loadVideos([url])
            }
        }
    }

    private func handleImportedFiles(_ urls: [URL]) {
        handleDroppedFiles(urls)
    }

    private func showOutputInFinder() {
        let doneVideos = viewModel.selectedVideos.filter { $0.status == .done && $0.outputURL != nil }
        if let firstURL = doneVideos.first?.outputURL {
            NSWorkspace.shared.selectFile(firstURL.path, inFileViewerRootedAtPath: firstURL.deletingLastPathComponent().path)
        } else if let firstGIF = viewModel.gifOutputURLs.first {
            NSWorkspace.shared.selectFile(firstGIF.path, inFileViewerRootedAtPath: firstGIF.deletingLastPathComponent().path)
        }
    }

    // MARK: - URL 加载辅助
    private func loadItemAsURL(from provider: NSItemProvider, type: String) async -> URL? {
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        return await withCheckedContinuation { continuation in
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
}

// MARK: - 视频条目行
struct VideoItemRow: View {
    let video: VideoItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(video.url.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text("MP4")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(3)
                }

                Text("\(video.width)×\(video.height) · \(formatDuration(video.duration))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !video.status.isProcessing {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch video.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.orange)
                .font(.system(size: 13))
        case .converting:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - GIF 条目行
struct GIFItemRow: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .foregroundColor(.purple)
                .font(.system(size: 13))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text("GIF")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(3)
                }

                Text(formatFileSize(url))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }

    private func formatFileSize(_ url: URL) -> String {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attr[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {}
        return ""
    }
}
