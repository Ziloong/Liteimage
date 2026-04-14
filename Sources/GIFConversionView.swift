import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct GIFConversionView: View {
    @StateObject private var viewModel = GIFConverterViewModel()
    @State private var isShowingFilePicker = false
    @State private var isDragging = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 主要内容区
                mainContentArea
                
                Divider()
                
                // 底部按钮区
                bottomButtonArea

                // 日志
                logSection

                // 输出按钮
                outputButtonSection
            }
            .padding(.vertical)
        }
        
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.movie, .video, UTType(filenameExtension: "mov")!, UTType(filenameExtension: "mp4")!, UTType(filenameExtension: "m4v")!].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { viewModel.loadVideo(url: url) }
            case .failure(let error):
                print("选择文件失败: \(error)")
            }
        }
        .onAppear {
            viewModel.checkFFmpegAvailability()
        }
    }

    // MARK: - 主要内容区：视频预览 + 设置面板
    @ViewBuilder
    private var mainContentArea: some View {
        HStack(alignment: .top, spacing: 20) {
            videoPreviewSection
            settingsPanelSection
        }
        .padding(.horizontal)
    }

    // MARK: - 视频预览区
    @ViewBuilder
    private var videoPreviewSection: some View {
        VStack(spacing: 0) {
            if viewModel.selectedVideoURL != nil {
                VideoPreviewView(url: viewModel.selectedVideoURL!)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(12)
                    .onDrop(of: [.movie, .video], isTargeted: $isDragging) { providers in
                        handleDrop(providers: providers)
                    }
            } else {
                VideoDropZoneView(
                    isDragging: $isDragging,
                    onDrop: { urls in
                        if let url = urls.first { viewModel.loadVideo(url: url) }
                    },
                    onClick: { isShowingFilePicker = true }
                )
                .frame(maxWidth: .infinity, maxHeight: 220)
                .onDrop(of: [.movie, .video], isTargeted: $isDragging) { providers in
                    handleDrop(providers: providers)
                }
            }

            if viewModel.selectedVideoURL != nil {
                videoInfoSection
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 视频信息
    @ViewBuilder
    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.selectedVideoURL?.lastPathComponent ?? "-")
                .font(.caption).fontWeight(.medium).lineLimit(1)

            HStack(spacing: 16) {
                Label(viewModel.videoResolution, systemImage: "rectangle.on.rectangle")
                Label(viewModel.formattedDuration, systemImage: "clock")
                Label(viewModel.videoFrameRate, systemImage: "film")
            }
            .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - 设置面板
    @ViewBuilder
    private var settingsPanelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 质量预设
            qualityPresetsSection
            
            // 输出设置滑块
            sliderSettingsSection
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .frame(width: 260)
    }

    // MARK: - 质量预设
    @ViewBuilder
    private var qualityPresetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.quality).font(.subheadline).fontWeight(.medium)

            HStack(spacing: 8) {
                ForEach(GIFQualityPreset.allCases, id: \.self) { preset in
                    QualityChip(
                        preset: preset,
                        isSelected: viewModel.selectedQuality == preset,
                        action: { viewModel.selectedQuality = preset }
                    )
                }
            }
        }
    }

    // MARK: - 滑块设置
    @ViewBuilder
    private var sliderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.outputSettings).font(.subheadline).fontWeight(.medium)

            WidthSliderRow(widthValue: $viewModel.outputWidth)

            Divider().padding(.vertical, 2)

            FramerateSliderRow(rateValue: $viewModel.frameRate)
        }
    }

    // MARK: - 底部按钮区
    @ViewBuilder
    private var bottomButtonArea: some View {
        HStack {
            if !viewModel.isConverting {
                Spacer()

                Button(action: { isShowingFilePicker = true }) {
                    Label(L.selectVideo, systemImage: "folder")
                }.buttonStyle(.bordered)

                Button(action: { viewModel.startConversion() }) {
                    Label(L.startConversion, systemImage: "play.fill")
                }.buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedVideoURL == nil)
            } else {
                ProgressView(value: viewModel.conversionProgress, total: 100)
                    .frame(maxWidth: 300)

                Button(action: { viewModel.stopConversion() }) {
                    Image(systemName: "stop.fill")
                }.buttonStyle(.bordered).tint(.red)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 日志
    @ViewBuilder
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.log).font(.caption).foregroundColor(.secondary)

            Text(viewModel.conversionLogs.isEmpty ? L.waitingForConversion : viewModel.conversionLogs.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(viewModel.conversionLogs.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
        }.padding(.horizontal)
    }

    // MARK: - 输出完成按钮
    @ViewBuilder
    private var outputButtonSection: some View {
        if let outputURL = viewModel.outputURL {
            HStack {
                Label(L.conversionDone, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green).font(.caption)
                Spacer()

                Button(action: {
                    NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
                }) {
                    Label(L.showInFinder, systemImage: "folder")
                }.buttonStyle(.bordered)
            }.padding(.horizontal)
        }
    }

    // MARK: - 拖放处理
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        for type in ["public.movie", "public.video"] where provider.hasItemConformingToTypeIdentifier(type) {
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    DispatchQueue.main.async { self.viewModel.loadVideo(url: url) }
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async { self.viewModel.loadVideo(url: url) }
                }
            }
            return true
        }

        return false
    }
}

// MARK: - 滑块行组件

// MARK: - 滑块行组件

struct WidthSliderRow: View {
    @Binding var widthValue: Int
    @State private var doubleValue: Double = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.width)
                    .font(.caption)
                Spacer()
                Text("\(widthValue) px")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Color.primary)
            }

            Slider(value: $doubleValue, in: 160...1280, step: 40) { _ in
                widthValue = Int(doubleValue.rounded())
            }
            .controlSize(.small)
        }
    }
}

struct FramerateSliderRow: View {
    @Binding var rateValue: Int
    @State private var doubleValue: Double = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.framerate)
                    .font(.caption)
                Spacer()
                Text("\(rateValue) FPS")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Color.primary)
            }

            Slider(value: $doubleValue, in: 5...30, step: 5) { _ in
                rateValue = Int(doubleValue.rounded())
            }
            .controlSize(.small)
        }
    }
}

// MARK: - 其他辅助视图

struct QualityChip: View {
    let preset: GIFQualityPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(preset.title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }.buttonStyle(.plain)
    }
}

struct VideoDropZoneView: View {
    @Binding var isDragging: Bool
    let onDrop: ([URL]) -> Void
    let onClick: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isDragging ? .blue : .gray.opacity(0.3))

            VStack(spacing: 12) {
                Image(systemName: "film").font(.system(size: 48)).foregroundColor(.secondary)
                Text(L.dropVideoTitle).font(.headline).foregroundColor(.secondary)
                Text(L.dropVideoSubtitle).font(.caption).foregroundColor(.secondary.opacity(0.7))
                Text(L.dropVideoHint).font(.caption2).foregroundColor(.secondary.opacity(0.5))
            }
        }
        .background(isDragging ? Color.blue.opacity(0.05) : Color.clear)
        .onTapGesture { onClick() }
    }
}

struct VideoPreviewView: View {
    let url: URL
    @State private var thumbnailImage: NSImage?

    var body: some View {
        ZStack {
            if let image = thumbnailImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }.onAppear { generateThumbnail() }
    }

    private func generateThumbnail() {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 400)

        Task {
            do {
                let cgImage = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
                await MainActor.run {
                    thumbnailImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            } catch {
                print("生成缩略图失败: \(error)")
            }
        }
    }
}
