import SwiftUI

struct PopoverView: View {
    let model: AppModel
    let manageCollections: () -> Void
    let openSettings: () -> Void
    let close: () -> Void
    let resize: (CGFloat) -> Void
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var category: SearchCategory = .recent
    @State private var filters = SearchFilters()
    @State private var showingFilters = false
    @State private var showingCollections = false
    @State private var renamingImage: ClipboardItem?
    @State private var newImageTitle = ""
    @FocusState private var searchFocused: Bool

    private var results: [SearchEntry] {
        Array(SearchBrowser.results(model: model, query: query, category: category, filters: filters).prefix(30))
    }

    private var panelHeight: CGFloat {
        128 + (results.isEmpty ? 92 : CGFloat(min(7, results.count)) * 56) + (model.pendingSensitive == nil ? 0 : 94)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard…", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onKeyPress(phases: .down, action: handleKey)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
                Button { showingFilters.toggle() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(filters.isActive ? Color.accentColor : Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(filters.isActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain).help("Filter results")
                .popover(isPresented: $showingFilters, arrowEdge: .bottom) {
                    SearchFilterPopover(model: model, category: $category, filters: $filters)
                }
            }.padding(.horizontal, 13).frame(height: 48)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(SearchCategory.allCases) { value in
                        Button { category = value; selectedIndex = 0 } label: {
                            Label(value.title, systemImage: value.symbol)
                                .font(.system(size: 11, weight: category == value ? .semibold : .medium))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(category == value ? Color.accentColor.opacity(0.17) : Color.primary.opacity(0.045), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 11).padding(.vertical, 8)
            }
            Divider().opacity(0.5)
            if model.pendingSensitive != nil { SensitiveBanner(model: model).padding(9); Divider() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                            SearchEntryRow(entry: entry, selected: index == selectedIndex)
                                .onTapGesture { choose(entry) }
                                .contextMenu {
                                    if case .item(let item) = entry {
                                        ItemContextMenu(item: item, model: model, renameImage: beginRename)
                                    }
                                    else if case .secret(let secret) = entry {
                                        Button("Copy Secret") { choose(.secret(secret)) }
                                    }
                                }
                        }
                    }.padding(.horizontal, 6).padding(.vertical, 5)
                }
                .onChange(of: selectedIndex) { _, value in
                    if results.indices.contains(value) {
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(results[value].id, anchor: .center) }
                    }
                }
                .overlay {
                    if results.isEmpty {
                        VStack(spacing: 5) {
                            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                                .font(.system(size: 19)).foregroundStyle(.tertiary)
                            Text(query.isEmpty ? "Nothing here yet" : "No matches")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(height: results.isEmpty ? 92 : CGFloat(min(7, results.count)) * 56)
            Divider()
            HStack(spacing: 11) {
                Text("↑↓ Navigate   ↵ Copy").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button { showingCollections = true } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.plain).help("Add to collection")
                    .popover(isPresented: $showingCollections) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add to Collection").font(.system(size: 12, weight: .semibold))
                            if model.collections.isEmpty { Text("No collections yet").foregroundStyle(.secondary) }
                            ForEach(model.collections) { collection in
                                Button(collection.name) {
                                    if results.indices.contains(selectedIndex), case .item(let item) = results[selectedIndex] {
                                        model.toggleCollection(item, id: collection.id)
                                    }
                                    showingCollections = false
                                }
                            }
                            Divider()
                            Button("Manage Collections…") { showingCollections = false; manageCollections() }
                        }.padding(13).frame(minWidth: 190, alignment: .leading)
                    }
                Button { openSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Settings")
            }.padding(.horizontal, 14).frame(height: 39)
        }
        .frame(width: 390, height: panelHeight)
        .preferredColorScheme(model.settings.colorScheme)
        .onAppear { resize(panelHeight); searchFocused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0; resize(panelHeight) }
        .onChange(of: category) { _, _ in selectedIndex = 0; resize(panelHeight) }
        .onChange(of: filters) { _, _ in selectedIndex = 0; resize(panelHeight) }
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

    private func choose(_ entry: SearchEntry, paste: Bool = false) {
        switch entry {
        case .item(let item): model.copy(item, paste: paste); close()
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
            selectedIndex = min(selectedIndex + 1, max(0, results.count - 1)); return .handled
        case .upArrow:
            selectedIndex = max(0, selectedIndex - 1); return .handled
        case .return:
            if results.indices.contains(selectedIndex) { choose(results[selectedIndex], paste: press.modifiers.contains(.command) || model.settings.pasteOnReturn) }
            return .handled
        case .escape: close(); return .handled
        case "d" where press.modifiers.contains(.command):
            if results.indices.contains(selectedIndex), case .item(let item) = results[selectedIndex] { model.toggleFavorite(item) }
            return .handled
        case "k" where press.modifiers.contains(.command): showingCollections = true; return .handled
        case .delete where press.modifiers.contains(.command):
            if results.indices.contains(selectedIndex), case .item(let item) = results[selectedIndex] { model.delete(item) }
            selectedIndex = min(selectedIndex, max(0, results.count - 1)); return .handled
        default: return .ignored
        }
    }
}
