import SwiftUI
import AppKit

struct ItemRow: View {
    let item: ClipboardItem
    let selected: Bool
    let compact: Bool
    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.09))
                if item.kind == .image, let path = item.thumbnailPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: 42, height: 42).clipped()
                } else if item.kind == .file, let path = item.filePaths.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit().padding(7)
                } else {
                    Image(systemName: item.kind.symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                }
            }.frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).lineLimit(compact ? 1 : 2).font(.system(size: 13, weight: .medium))
                HStack(spacing: 5) {
                    Text(item.subtitle)
                    Text("·")
                    Text(item.copiedAt, style: .relative)
                    if let source = item.sourceApp { Text("·"); Text(source).lineLimit(1) }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if item.isFavorite { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.yellow) }
        }
        .padding(.horizontal, 9).padding(.vertical, compact ? 4 : 6)
        .background(selected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

struct ItemContextMenu: View {
    let item: ClipboardItem
    let model: AppModel
    let renameImage: (ClipboardItem) -> Void
    var body: some View {
        Button("Copy") { model.copy(item) }
        Button("Copy and Paste") { model.copy(item, paste: true) }
        if let text = item.text {
            Button("Copy as Plain Text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        }
        if item.kind == .url, let text = item.text {
            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
            if let url = URL(string: text) { Button("Open URL") { NSWorkspace.shared.open(url) } }
        }
        Divider()
        Button(item.isFavorite ? "Remove Favorite" : "Favorite") { model.toggleFavorite(item) }
        Menu("Collections") {
            ForEach(model.collections) { collection in
                Button { model.toggleCollection(item, id: collection.id) } label: {
                    Label(collection.name, systemImage: item.collectionIDs.contains(collection.id) ? "checkmark.circle.fill" : "circle")
                }
            }
        }
        Menu("Change Type") {
            ForEach(ItemKind.allCases) { kind in Button(kind.title) { model.setKind(item, to: kind) } }
        }
        if let text = item.text {
            Button("Save as Secret") { model.storeSecret(value: text, title: "Saved Secret", category: "Secret", removing: item) }
        }
        if item.kind == .file, let path = item.filePaths.first {
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        }
        if item.kind == .image, let path = item.imagePath {
            Divider()
            Button("Rename Image…") { renameImage(item) }
            Button("Open Image") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            Button("Export Image…") {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "Clipboard Image.png"
                if panel.runModal() == .OK, let destination = panel.url {
                    try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: destination)
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(item) }
    }
}

struct SensitiveBanner: View {
    let model: AppModel
    var body: some View {
        if let pending = model.pendingSensitive {
            VStack(alignment: .leading, spacing: 7) {
                Label("Sensitive content detected", systemImage: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                Text("Possible \(pending.category.lowercased()). It has not been saved to history.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Store Securely") { model.storeSecret(value: pending.value, title: pending.category, category: pending.category,
                                                                   sourceApp: pending.sourceApp, sourceBundleID: pending.sourceBundleID) }
                    Button("Keep Temporarily") { model.keepSensitiveTemporarily() }
                    Button("Ignore") { model.ignoreSensitive() }
                }.controlSize(.small)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
