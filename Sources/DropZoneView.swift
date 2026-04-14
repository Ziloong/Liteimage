import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void
    let onTap: () -> Void
    var acceptedExtensions: [String] = ["png", "jpg", "jpeg", "gif"]
    var dropTitle: String = L.dropImageTitle
    var dropSubtitle: String = L.dropImageSubtitle
    var dropHint: String = L.dropImageHint
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(isTargeted ? .orange : .secondary)
            
            Text(dropTitle)
                .font(.headline)
                .foregroundColor(isTargeted ? .primary : .secondary)
            
            Text(dropSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(dropHint)
                .font(.caption)
                .foregroundColor(.secondary)
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
        .onTapGesture {
            onTap()
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        
        Task {
            var urls: [URL] = []
            
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    // 检查文件扩展名
                    let ext = url.pathExtension.lowercased()
                    if acceptedExtensions.contains(ext) {
                        urls.append(url)
                    }
                }
            }
            
            await MainActor.run {
                if !urls.isEmpty {
                    onDrop(urls)
                }
            }
        }
        
        return true
    }
    
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
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
