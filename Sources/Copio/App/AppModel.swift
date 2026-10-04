import AppKit
import ServiceManagement

@MainActor @Observable final class AppModel {
    let settings = AppSettings()
    let database: Database
    var items: [ClipboardItem] = []
    var collections: [ClipCollection] = []
    var secrets: [SecureItem] = []
    var pendingSensitive: (value: String, category: String, sourceApp: String?, sourceBundleID: String?)?
    var alertMessage: String?
    var search = ""
    var selection: SidebarSelection = .all
    var selectedItemID: UUID?
    var previousApplication: NSRunningApplication?
    var shortcutAvailable = true
    private var temporaryItemIDs: Set<UUID> = []
    private var monitor: ClipboardMonitor!
    private var cleanupTimer: Timer?
    private var lastCleanup = Date.distantPast

    init(database suppliedDatabase: Database? = nil, startMonitoring: Bool = true, performCleanup: Bool = true) throws {
        database = try suppliedDatabase ?? Database()
        items = database.items()
        collections = database.collections()
        secrets = database.secrets()
        monitor = ClipboardMonitor { [weak self] pasteboard, potentialSources in self?.capture(pasteboard, potentialSources: potentialSources) }
        if startMonitoring && settings.monitorEnabled { monitor.start() }
        if performCleanup {
            cleanup()
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.cleanup() }
            }
            cleanupTimer?.tolerance = 300
        }
    }

    func syncMonitoring() { settings.monitorEnabled ? monitor.start() : monitor.stop() }

    func isTemporarySensitive(_ item: ClipboardItem) -> Bool { temporaryItemIDs.contains(item.id) }

    private func capture(_ board: NSPasteboard, potentialSources: Set<String>) {
        guard settings.monitorEnabled else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier ?? ""
        let excluded = Set(settings.excludedBundleIDs.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard excluded.isDisjoint(with: potentialSources), bundleID != Bundle.main.bundleIdentifier else { return }
        if settings.detectSensitive, let text = board.string(forType: .string),
           let category = ClassificationService.sensitiveCategory(for: text) {
            pendingSensitive = (text, category, app?.localizedName, app?.bundleIdentifier)
            if settings.showNotifications { Task { await NotificationService.notifySensitiveContent() } }
            return
        }
        guard var item = ClipboardCapture.read(from: board, directory: database.directory,
                                               captureImages: settings.captureImages, captureFiles: settings.captureFiles,
                                               sourceApp: app?.localizedName, sourceBundleID: app?.bundleIdentifier) else { return }
        if settings.ignoreDuplicates, let previous = items.first, previous.contentHash == item.contentHash { return }
        item.createdAt = .now
        do {
            try database.save(item)
            items.insert(item, at: 0)
            if selectedItemID == nil { selectedItemID = item.id }
            if items.count > 12_000 { items.removeLast(items.count - 12_000) }
            if Date.now.timeIntervalSince(lastCleanup) > 60 { cleanup() }
        } catch { alertMessage = error.localizedDescription }
    }

    func filteredItems(query: String? = nil, selection: SidebarSelection? = nil) -> [ClipboardItem] {
        let query = (query ?? search).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selection = selection ?? self.selection
        let tokens = query.split(separator: " ").map(String.init)
        let collectionNames = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0.name) })
        return items.filter { item in
            let matchingSection: Bool
            switch selection {
            case .all: matchingSection = true
            case .favorites: matchingSection = item.isFavorite
            case .images: matchingSection = item.kind == .image
            case .urls: matchingSection = item.kind == .url
            case .code: matchingSection = item.kind == .code
            case .files: matchingSection = item.kind == .file
            case .secure: matchingSection = false
            case .collection(let id): matchingSection = item.collectionIDs.contains(id)
            case .smart(let name):
                switch name { case "Emails": matchingSection = (item.text ?? "").contains("@")
                default: matchingSection = item.kind.title == name || item.kind.title + "s" == name }
            }
            guard matchingSection else { return false }
            if tokens.isEmpty { return true }
            let matchingNames = item.collectionIDs.compactMap { collectionNames[$0] }.joined(separator: " ")
            let haystack = ([item.title, item.displayTitle, item.text ?? "", item.sourceApp ?? "", matchingNames] + item.filePaths)
                .joined(separator: " ").lowercased()
            return tokens.allSatisfy { token in
                if haystack.contains(token) { return true }
                var iterator = haystack.makeIterator()
                return token.allSatisfy { character in
                    while let next = iterator.next() { if next == character { return true } }
                    return false
                }
            }
        }
    }

    func copy(_ item: ClipboardItem, paste: Bool = false) {
        guard PasteService.write(item) else { alertMessage = "The original content is unavailable."; return }
        monitor.skipCurrentChange()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].copiedAt = .now
            if !temporaryItemIDs.contains(item.id) { try? database.save(items[index]) }
            let updated = items.remove(at: index)
            items.insert(updated, at: 0)
        }
        if paste && !PasteService.paste(to: previousApplication) {
            alertMessage = "Copied. Enable Accessibility access in System Settings to paste automatically."
        }
    }

    func toggleFavorite(_ item: ClipboardItem) { mutate(item) { $0.isFavorite.toggle() } }
    func renameItem(_ item: ClipboardItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(item) { $0.title = trimmed }
    }
    func setKind(_ item: ClipboardItem, to kind: ItemKind) { mutate(item) { $0.kind = kind } }
    func toggleCollection(_ item: ClipboardItem, id: UUID) {
        mutate(item) { if !$0.collectionIDs.insert(id).inserted { $0.collectionIDs.remove(id) } }
    }

    private func mutate(_ item: ClipboardItem, action: (inout ClipboardItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard !temporaryItemIDs.contains(item.id) else {
            alertMessage = "Temporary sensitive items cannot be organized. Store this item securely first."
            return
        }
        action(&items[index])
        do { try database.save(items[index]) } catch { alertMessage = error.localizedDescription }
    }

    func delete(_ item: ClipboardItem) {
        if temporaryItemIDs.remove(item.id) != nil {
            items.removeAll { $0.id == item.id }
            return
        }
        do {
            try database.deleteItem(item.id)
            items.removeAll { $0.id == item.id }
            if selectedItemID == item.id { selectedItemID = items.first?.id }
            removeUnusedAssets(for: item)
        }
        catch { alertMessage = error.localizedDescription }
    }

    func clearHistory() {
        do {
            let oldItems = items
            try database.clearHistory()
            items = []
            selectedItemID = nil
            removeUnusedAssets(for: oldItems)
            database.purgeDeletedContent()
        }
        catch { alertMessage = error.localizedDescription }
    }

    private func removeUnusedAssets(for item: ClipboardItem) {
        for path in [item.imagePath, item.thumbnailPath, item.richTextPath].compactMap({ $0 }) {
            guard !items.contains(where: { $0.imagePath == path || $0.thumbnailPath == path || $0.richTextPath == path }) else { continue }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func removeUnusedAssets(for removed: [ClipboardItem]) {
        let activePaths = Set(items.flatMap { [$0.imagePath, $0.thumbnailPath, $0.richTextPath].compactMap { $0 } })
        let removedPaths = Set(removed.flatMap { [$0.imagePath, $0.thumbnailPath, $0.richTextPath].compactMap { $0 } })
        for path in removedPaths.subtracting(activePaths) { try? FileManager.default.removeItem(atPath: path) }
    }

    func cleanup() {
        lastCleanup = .now
        let cutoff = settings.cleanupDays > 0 ? Calendar.current.date(byAdding: .day, value: -settings.cleanupDays, to: .now) : nil
        var keptCount = 0
        let previousItems = items
        var idsToDelete: [UUID] = []
        for item in previousItems {
            let protected = (settings.keepFavorites && item.isFavorite) || (settings.keepCollections && !item.collectionIDs.isEmpty)
            let expired = cutoff.map { item.copiedAt < $0 } ?? false
            let overLimit = settings.historyLimit > 0 && keptCount >= settings.historyLimit
            if !protected && (expired || overLimit) { idsToDelete.append(item.id) }
            else if !protected { keptCount += 1 }
        }
        do { try database.deleteItems(idsToDelete) }
        catch { alertMessage = error.localizedDescription; return }
        items = database.items()
        temporaryItemIDs = []
        let keptIDs = Set(items.map(\.id))
        removeUnusedAssets(for: previousItems.filter { !keptIDs.contains($0.id) })
    }

    func addCollection(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let collection = ClipCollection(name: trimmed, sortOrder: collections.count)
        do { try database.save(collection); collections.append(collection) }
        catch { alertMessage = error.localizedDescription }
    }

    func saveCollection(_ collection: ClipCollection) {
        do { try database.save(collection); if let index = collections.firstIndex(where: { $0.id == collection.id }) { collections[index] = collection } }
        catch { alertMessage = error.localizedDescription }
    }

    func moveCollection(_ collection: ClipCollection, by offset: Int) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }),
              collections.indices.contains(index + offset) else { return }
        collections.swapAt(index, index + offset)
        for index in collections.indices {
            collections[index].sortOrder = index
            try? database.save(collections[index])
        }
    }

    func deleteCollection(_ collection: ClipCollection) {
        do {
            try database.deleteCollection(collection.id)
            collections.removeAll { $0.id == collection.id }
            for item in items where item.collectionIDs.contains(collection.id) { toggleCollection(item, id: collection.id) }
            if selection == .collection(collection.id) { selection = .all }
        } catch { alertMessage = error.localizedDescription }
    }

    func storeSecret(value: String, title: String, category: String, removing item: ClipboardItem? = nil,
                     sourceApp: String? = nil, sourceBundleID: String? = nil) {
        let secret = SecureItem(title: title, category: category, sourceApp: sourceApp ?? item?.sourceApp,
                                sourceBundleID: sourceBundleID ?? item?.sourceBundleID)
        do {
            try KeychainService.store(value, id: secret.id)
            do { try database.save(secret) }
            catch { KeychainService.delete(id: secret.id); throw error }
            if let item {
                if temporaryItemIDs.remove(item.id) == nil {
                    do { try database.deleteItem(item.id) }
                    catch {
                        try? database.deleteSecret(secret.id)
                        KeychainService.delete(id: secret.id)
                        throw error
                    }
                    database.purgeDeletedContent()
                }
                items.removeAll { $0.id == item.id }
                removeUnusedAssets(for: item)
            }
            secrets.insert(secret, at: 0)
            pendingSensitive = nil
        } catch { alertMessage = error.localizedDescription }
    }

    func ignoreSensitive() { pendingSensitive = nil }

    func keepSensitiveTemporarily() {
        guard let pendingSensitive else { return }
        var item = ClipboardItem(kind: .text, title: "••••••••••", text: pendingSensitive.value,
                                 contentHash: UUID().uuidString, sourceApp: pendingSensitive.sourceApp,
                                 sourceBundleID: pendingSensitive.sourceBundleID)
        item.copiedAt = .now
        // Temporary sensitive content stays in memory and is removed on the next cleanup.
        items.insert(item, at: 0)
        temporaryItemIDs.insert(item.id)
        self.pendingSensitive = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            if temporaryItemIDs.remove(item.id) != nil { items.removeAll { $0.id == item.id } }
        }
    }

    func revealSecret(_ secret: SecureItem) async -> String? {
        do { return try await KeychainService.retrieve(id: secret.id, authenticate: settings.requireAuthentication) }
        catch { alertMessage = error.localizedDescription; return nil }
    }

    func copySecret(_ secret: SecureItem, paste: Bool = false) async {
        guard let value = await revealSecret(secret) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(value, forType: .string)
        let changeCount = board.changeCount
        monitor.skipCurrentChange()
        if let index = secrets.firstIndex(where: { $0.id == secret.id }) {
            secrets[index].lastUsedAt = .now
            try? database.save(secrets[index])
        }
        if paste && !PasteService.paste(to: previousApplication) {
            alertMessage = "Copied. Enable Accessibility access in System Settings to paste automatically."
        }
        let seconds = settings.secretClearSeconds
        if seconds > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if board.changeCount == changeCount { board.clearContents(); monitor.skipCurrentChange() }
            }
        }
    }

    func deleteSecret(_ secret: SecureItem) {
        do { try database.deleteSecret(secret.id); KeychainService.delete(id: secret.id); secrets.removeAll { $0.id == secret.id } }
        catch { alertMessage = error.localizedDescription }
    }

    func syncLaunchAtLogin() {
        do {
            if settings.launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { alertMessage = "Could not change Login Items. Check System Settings." }
    }

    func resetApplication() {
        do {
            try database.resetAll()
            for secret in secrets { KeychainService.delete(id: secret.id) }
            for folder in ["Images", "RichText"] {
                try? FileManager.default.removeItem(at: database.directory.appendingPathComponent(folder, isDirectory: true))
            }
            items = []
            collections = []
            secrets = []
            temporaryItemIDs = []
            pendingSensitive = nil
            let hadLoginItem = settings.launchAtLogin
            settings.resetToDefaults()
            syncMonitoring()
            if hadLoginItem { syncLaunchAtLogin() }
            alertMessage = "Application data and settings were reset. Onboarding will appear on the next launch."
        } catch { alertMessage = error.localizedDescription }
    }

    func exportHistory(to destination: URL) {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            let assets = temporary.appendingPathComponent("Assets", isDirectory: true)
            try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
            let assetFields: [(String, WritableKeyPath<ClipboardItem, String?>)] = [
                ("image.png", \.imagePath), ("thumbnail.png", \.thumbnailPath), ("rich.rtf", \.richTextPath)
            ]
            let exportedItems = try items.filter { !temporaryItemIDs.contains($0.id) }.map { item -> ClipboardItem in
                var copy = item
                for (suffix, keyPath) in assetFields {
                    guard let path = copy[keyPath: keyPath] else { continue }
                    guard fileManager.fileExists(atPath: path) else { copy[keyPath: keyPath] = nil; continue }
                    let name = "\(item.id.uuidString)-\(suffix)"
                    try fileManager.copyItem(at: URL(fileURLWithPath: path), to: assets.appendingPathComponent(name))
                    copy[keyPath: keyPath] = "Assets/\(name)"
                }
                return copy
            }
            let archive = ClipArchive(version: 1, exportedAt: .now, items: exportedItems, collections: collections)
            try JSONEncoder().encode(archive).write(to: temporary.appendingPathComponent("manifest.json"), options: .atomic)
            if fileManager.fileExists(atPath: destination.path) { throw ArchiveError.destinationExists }
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            alertMessage = error.localizedDescription
        }
    }

    func importHistory(from source: URL) {
        do {
            let data = try Data(contentsOf: source.appendingPathComponent("manifest.json"))
            let archive = try JSONDecoder().decode(ClipArchive.self, from: data)
            guard archive.version == 1 else { throw ArchiveError.unsupportedVersion }
            for collection in archive.collections { try database.save(collection) }
            let manager = FileManager.default
            let assetFields: [(String, WritableKeyPath<ClipboardItem, String?>)] = [
                ("Images", \.imagePath), ("Images", \.thumbnailPath), ("RichText", \.richTextPath)
            ]
            for archived in archive.items {
                var item = archived
                for (directory, keyPath) in assetFields {
                    guard let relative = item[keyPath: keyPath] else { continue }
                    guard relative.hasPrefix("Assets/"), !relative.contains(".."), !relative.contains("\\") else { throw ArchiveError.invalidAsset }
                    let input = source.appendingPathComponent(relative)
                    let assetsRoot = source.appendingPathComponent("Assets", isDirectory: true).resolvingSymlinksInPath().path + "/"
                    guard input.resolvingSymlinksInPath().path.hasPrefix(assetsRoot) else { throw ArchiveError.invalidAsset }
                    let outputDirectory = database.directory.appendingPathComponent(directory, isDirectory: true)
                    try manager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                    let output = outputDirectory.appendingPathComponent(item.id.uuidString + "-" + input.lastPathComponent)
                    if !manager.fileExists(atPath: output.path) { try manager.copyItem(at: input, to: output) }
                    item[keyPath: keyPath] = output.path
                }
                try database.save(item)
            }
            collections = database.collections()
            items = database.items()
            cleanup()
        } catch { alertMessage = error.localizedDescription }
    }
}

enum ArchiveError: LocalizedError {
    case destinationExists, unsupportedVersion, invalidAsset
    var errorDescription: String? {
        switch self {
        case .destinationExists: "The export destination already exists."
        case .unsupportedVersion: "This archive version is not supported."
        case .invalidAsset: "The archive contains an invalid asset path."
        }
    }
}
