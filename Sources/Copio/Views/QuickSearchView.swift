import AppKit
import SwiftUI

struct QuickSearchView: View {
    let model: AppModel
    let choose: (ClipboardItem, Bool) -> Void
    let close: () -> Void
    let manageCollections: () -> Void
    let openSettings: () -> Void
    let resize: (CGFloat) -> Void

    @State private var query = ""
    @State private var category: SearchCategory = .recent
    @State private var searchFilters = SearchFilters()
    @State private var showingFilters = false
    @State private var selectedIndex = 0
    @State private var showingCollections = false
    @State private var renamingImage: ClipboardItem?
    @State private var newImageTitle = ""
    @FocusState private var searchFocused: Bool

    private var results: [SearchEntry] {
        Array(SearchBrowser.results(model: model, query: query, category: category, filters: searchFilters).prefix(50))
    }

    private var panelHeight: CGFloat {
        let rows = CGFloat(min(7, results.count))
        return 148 + (results.isEmpty ? 96 : rows * 56) + (model.pendingSensitive == nil ? 0 : 94)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.55)
            filters
            if model.pendingSensitive != nil {
                SensitiveBanner(model: model).padding(.horizontal, 12).padding(.bottom, 6)
            }
            Divider().opacity(0.45)
            resultsArea
            Divider().opacity(0.45)
            footer
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.13), lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .preferredColorScheme(model.settings.colorScheme)
        .onAppear {
            resize(panelHeight)
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { _, _ in selectedIndex = 0; resize(panelHeight) }
        .onChange(of: category) { _, _ in selectedIndex = 0; resize(panelHeight) }
        .onChange(of: searchFilters) { _, _ in selectedIndex = 0; resize(panelHeight) }
        .onChange(of: model.items.count) { _, _ in resize(panelHeight) }
        .onChange(of: model.secrets.count) { _, _ in resize(panelHeight) }
        .onChange(of: model.pendingSensitive?.category) { _, _ in resize(panelHeight) }
        .alert("Copio", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
        .alert("Rename Image", isPresented: Binding(get: { renamingImage != nil }, set: { if !$0 { renamingImage = nil } })) {
            TextField("Image name", text: $newImageTitle)
            Button("Save") {
                if let renamingImage { model.renameItem(renamingImage, to: newImageTitle) }
                renamingImage = nil
            }
            Button("Cancel", role: .cancel) { renamingImage = nil }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 13) {
            Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .medium)).foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .regular))
                .focused($searchFocused)
                .onKeyPress(phases: .down, action: handleKey)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            } else {
                Text(model.settings.shortcutDisplay).font(.system(size: 11, design: .rounded)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
            Button { showingFilters.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundStyle(searchFilters.isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 29, height: 29)
                    .background(searchFilters.isActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain).help("Filter results")
            .popover(isPresented: $showingFilters, arrowEdge: .bottom) {
                SearchFilterPopover(model: model, category: $category, filters: $searchFilters)
            }
        }
        .padding(.horizontal, 19).frame(height: 62)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SearchCategory.allCases) { value in filterButton(value) }
            }.padding(.horizontal, 13)
        }
        .frame(height: 39)
    }

    private var resultsArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        SearchEntryRow(entry: entry, selected: selectedIndex == index)
                            .onTapGesture { chooseEntry(entry, paste: false) }
                            .contextMenu {
                                if case .item(let item) = entry {
                                    ItemContextMenu(item: item, model: model, renameImage: beginRename)
                                }
                                else if case .secret(let secret) = entry {
                                    Button("Copy Secret") { chooseEntry(.secret(secret), paste: false) }
                                }
                            }
                    }
                }.padding(.horizontal, 7).padding(.vertical, 3)
            }
            .frame(height: results.isEmpty ? 96 : CGFloat(min(7, results.count)) * 56)
            .overlay {
                if results.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                            .font(.system(size: 19)).foregroundStyle(.tertiary)
                        Text(query.isEmpty ? "Nothing copied yet" : "No matching items")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: selectedIndex) { _, index in
                if results.indices.contains(index) {
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(results[index].id, anchor: .center) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("↑↓  Navigate").foregroundStyle(.secondary)
            Text("↵  Copy").foregroundStyle(.secondary)
            Text("⌘↵  Paste").foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { showingCollections = true } label: { Image(systemName: "folder.badge.plus") }
                .buttonStyle(.plain).help("Add selected item to collection (⌘K)")
                .popover(isPresented: $showingCollections) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add to Collection").font(.system(size: 12, weight: .semibold))
                        if model.collections.isEmpty { Text("Create a collection in Settings.").foregroundStyle(.secondary) }
                        ForEach(model.collections) { collection in
                            Button {
                                if results.indices.contains(selectedIndex), case .item(let item) = results[selectedIndex] {
                                    model.toggleCollection(item, id: collection.id)
                                }
                                showingCollections = false
                            } label: {
                                Label(collection.name, systemImage: collection.symbol)
                            }.buttonStyle(.plain)
                        }
                        Divider()
                        Button("Manage Collections…") { showingCollections = false; manageCollections() }
                    }.padding(13).frame(minWidth: 190, alignment: .leading)
                }
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).help("Settings")
        }
        .font(.system(size: 10))
        .padding(.horizontal, 18).frame(height: 43)
    }

    private func filterButton(_ value: SearchCategory) -> some View {
        Button { category = value } label: {
            Label(value.title, systemImage: value.symbol).font(.system(size: 11, weight: category == value ? .semibold : .medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(category == value ? Color.accentColor.opacity(0.16) : Color.clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func chooseEntry(_ entry: SearchEntry, paste: Bool) {
        switch entry {
        case .item(let item): choose(item, paste)
        case .secret(let secret):
            Task { await model.copySecret(secret, paste: paste); if model.alertMessage == nil { close() } }
        }
    }

    private func beginRename(_ item: ClipboardItem) {
        newImageTitle = item.displayTitle
        renamingImage = item
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .downArrow:
            selectedIndex = min(selectedIndex + 1, max(0, results.count - 1))
            return .handled
        case .upArrow:
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        case .return:
            if results.indices.contains(selectedIndex) {
                chooseEntry(results[selectedIndex], paste: press.modifiers.contains(.command) || model.settings.pasteOnReturn)
            }
            return .handled
        case .escape:
            close()
            return .handled
        case "d" where press.modifiers.contains(.command):
            if results.indices.contains(selectedIndex), case .item(let item) = results[selectedIndex] { model.toggleFavorite(item) }
            return .handled
        case "k" where press.modifiers.contains(.command):
            showingCollections = true
            return .handled
        case .delete where press.modifiers.contains(.command):
            if results.indices.contains(selectedIndex), case .item(let item) = results[selectedIndex] { model.delete(item) }
            selectedIndex = min(selectedIndex, max(0, results.count - 1))
            return .handled
        default:
            return .ignored
        }
    }
}
