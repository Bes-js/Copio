import AppKit
import SwiftUI

enum SearchCategory: String, CaseIterable, Identifiable {
    case recent, favorites, images, urls, passwords, folders, files, code

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .recent: "clock"
        case .favorites: "star"
        case .images: "photo"
        case .urls: "link"
        case .passwords: "lock"
        case .folders: "folder"
        case .files: "doc"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum SearchPeriod: Int, CaseIterable, Identifiable {
    case any = 0, today = 1, week = 7, month = 30
    var id: Int { rawValue }
    var title: String {
        switch self { case .any: "Any time"; case .today: "Today"; case .week: "Past 7 days"; case .month: "Past 30 days" }
    }
}

enum SearchSort: String, CaseIterable, Identifiable {
    case newest, oldest
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct SearchFilters: Equatable {
    var sourceApp = ""
    var period: SearchPeriod = .any
    var favoritesOnly = false
    var inCollectionOnly = false
    var sort: SearchSort = .newest
    var isActive: Bool { !sourceApp.isEmpty || period != .any || favoritesOnly || inCollectionOnly || sort != .newest }
}

enum SearchEntry: Identifiable {
    case item(ClipboardItem)
    case secret(SecureItem)

    var id: String {
        switch self { case .item(let item): "item-\(item.id)"; case .secret(let secret): "secret-\(secret.id)" }
    }
    var date: Date {
        switch self { case .item(let item): item.copiedAt; case .secret(let secret): secret.lastUsedAt ?? secret.createdAt }
    }
    var sourceApp: String? {
        switch self { case .item(let item): item.sourceApp; case .secret(let secret): secret.sourceApp }
    }
    var sourceBundleID: String? {
        switch self { case .item(let item): item.sourceBundleID; case .secret(let secret): secret.sourceBundleID }
    }
}

@MainActor enum SearchBrowser {
    static func results(model: AppModel, query: String, category: SearchCategory, filters: SearchFilters) -> [SearchEntry] {
        let items = model.filteredItems(query: query, selection: .all).filter { item in
            switch category {
            case .recent: true
            case .favorites: item.isFavorite
            case .images: item.kind == .image
            case .urls: item.kind == .url
            case .passwords: false
            case .folders: !item.collectionIDs.isEmpty
            case .files: item.kind == .file
            case .code: item.kind == .code
            }
        }.map(SearchEntry.item)
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace)
        let secrets: [SearchEntry] = [.recent, .passwords].contains(category) ? model.secrets.filter { secret in
            let searchable = [secret.title, secret.category, secret.sourceApp ?? ""].joined(separator: " ").lowercased()
            return tokens.allSatisfy { searchable.contains($0) }
        }.map(SearchEntry.secret) : []
        let cutoff = filters.period == .any ? Date.distantPast : Date.now.addingTimeInterval(-Double(filters.period.rawValue) * 86_400)
        return (items + secrets).filter { entry in
            guard entry.date >= cutoff else { return false }
            if !filters.sourceApp.isEmpty && entry.sourceApp != filters.sourceApp { return false }
            if filters.favoritesOnly {
                guard case .item(let item) = entry, item.isFavorite else { return false }
            }
            if filters.inCollectionOnly {
                guard case .item(let item) = entry, !item.collectionIDs.isEmpty else { return false }
            }
            return true
        }.sorted { filters.sort == .newest ? $0.date > $1.date : $0.date < $1.date }
    }
}

struct SearchFilterPopover: View {
    let model: AppModel
    @Binding var category: SearchCategory
    @Binding var filters: SearchFilters

    private var sources: [String] {
        Set(model.items.compactMap(\.sourceApp) + model.secrets.compactMap(\.sourceApp)).sorted()
    }

    private func bundleID(for name: String) -> String? {
        model.items.first(where: { $0.sourceApp == name })?.sourceBundleID
            ?? model.secrets.first(where: { $0.sourceApp == name })?.sourceBundleID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Filters", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                Spacer()
                if filters.isActive || category != .recent {
                    Button("Reset") { filters = SearchFilters(); category = .recent }.buttonStyle(.plain).foregroundStyle(.tint)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2").frame(width: 15).foregroundStyle(.secondary)
                Text("Type")
                Spacer()
                Picker("", selection: $category) {
                    ForEach(SearchCategory.allCases) { value in Label(value.title, systemImage: value.symbol).tag(value) }
                }.labelsHidden().frame(width: 150)
            }
            HStack(spacing: 8) {
                Image(systemName: "app.connected.to.app.below.fill").frame(width: 15).foregroundStyle(.secondary)
                Text("Source")
                Spacer()
                Picker("", selection: $filters.sourceApp) {
                    Label("All apps", systemImage: "square.grid.2x2").tag("")
                    ForEach(sources, id: \.self) { source in
                        Label { Text(source) } icon: { SourceAppIcon(name: source, bundleID: bundleID(for: source), size: 14) }
                            .tag(source)
                    }
                }.labelsHidden().frame(width: 150)
            }
            HStack(spacing: 8) {
                Image(systemName: "calendar").frame(width: 15).foregroundStyle(.secondary)
                Text("Date")
                Spacer()
                Picker("", selection: $filters.period) {
                    ForEach(SearchPeriod.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 150)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down").frame(width: 15).foregroundStyle(.secondary)
                Text("Sort")
                Spacer()
                Picker("", selection: $filters.sort) {
                    ForEach(SearchSort.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 150)
            }
            Divider()
            HStack(spacing: 7) {
                filterChip("Favorites", symbol: "star", isOn: $filters.favoritesOnly)
                filterChip("In folders", symbol: "folder", isOn: $filters.inCollectionOnly)
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .padding(12)
        .frame(width: 275)
    }

    private func filterChip(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(isOn.wrappedValue ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct SearchEntryRow: View {
    let entry: SearchEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                switch entry {
                case .item(let item):
                    if item.kind == .image, let path = item.thumbnailPath, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: 38, height: 38).clipped()
                    } else if item.kind == .file, let path = item.filePaths.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit().padding(6)
                    } else {
                        Image(systemName: item.kind.symbol).font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                case .secret:
                    Image(systemName: "lock.fill").font(.system(size: 16)).foregroundStyle(.secondary)
                }
            }.frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                switch entry {
                case .item(let item):
                    Text(item.displayTitle).lineLimit(1).font(.system(size: 13, weight: .medium))
                    metadata(type: item.subtitle, date: item.copiedAt, source: item.sourceApp, bundleID: item.sourceBundleID)
                case .secret(let secret):
                    Text("••••••••••••").font(.system(size: 13, weight: .medium, design: .monospaced))
                    metadata(type: secret.category, date: secret.lastUsedAt ?? secret.createdAt,
                             source: secret.sourceApp, bundleID: secret.sourceBundleID)
                }
            }
            Spacer(minLength: 2)
            if case .item(let item) = entry, item.isFavorite {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 9).frame(height: 54)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func metadata(type: String, date: Date, source: String?, bundleID: String?) -> some View {
        HStack(spacing: 5) {
            Text(type)
            Text("·")
            Text(date, style: .relative)
            if let source, !source.isEmpty {
                Text("·")
                SourceAppIcon(name: source, bundleID: bundleID, size: 11)
                Text(source).lineLimit(1)
            }
            else { Text("·"); Text("Source unknown").lineLimit(1) }
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

@MainActor private enum SourceAppArtwork {
    static func icon(name: String, bundleID: String?) -> NSImage? {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            (bundleID != nil && $0.bundleIdentifier == bundleID) || $0.localizedName == name
        }), let icon = running.icon { return icon }
        let knownIDs = [
            "Finder": "com.apple.finder", "Google Chrome": "com.google.Chrome", "Safari": "com.apple.Safari",
            "Notes": "com.apple.Notes", "Preview": "com.apple.Preview", "Photos": "com.apple.Photos",
            "Firefox": "org.mozilla.firefox", "Visual Studio Code": "com.microsoft.VSCode",
            "Slack": "com.tinyspeck.slackmacgap", "Discord": "com.hnc.Discord", "ChatGPT": "com.openai.codex"
        ]
        guard let id = bundleID ?? knownIDs[name],
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct SourceAppIcon: View {
    let name: String
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = SourceAppArtwork.icon(name: name, bundleID: bundleID) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
