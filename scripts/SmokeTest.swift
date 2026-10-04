import Foundation
import AppKit

enum SmokeFailure: Error { case check(String) }

@main struct SmokeTest {
    static func main() async throws {
        try check(ClassificationService.kind(for: "https://example.com/path", hasRichText: false) == .url, "URL classification")
        try check(ClassificationService.kind(for: "func run() {\n return 1\n}", hasRichText: false) == .code, "code classification")
        try check(ClassificationService.sensitiveCategory(for: "ordinary clipboard text") == nil, "conservative detection")
        try check(ClassificationService.sensitiveCategory(for: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----") == "Private key", "private key detection")
        try check(ClassificationService.sensitiveCategory(for: "4111 1111 1111 1111") == "Credit card-like data", "card-like detection")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        board.clearContents()
        board.setString("https://example.com/clip", forType: .string)
        guard let item = ClipboardCapture.read(from: board, directory: directory, captureImages: false, captureFiles: false,
                                               sourceApp: "Test App", sourceBundleID: "org.example.test") else {
            throw SmokeFailure.check("text capture")
        }
        try check(item.kind == .url && item.sourceApp == "Test App" && item.sourceBundleID == "org.example.test", "text capture metadata")
        let database = try Database(directory: directory)
        try database.save(item)
        try check(database.items().first?.text == "https://example.com/clip", "history persistence")
        try database.deleteItem(item.id)
        try check(database.items().isEmpty, "history deletion")

        let monitorBoard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let probe = await MainActor.run { MonitorProbe(board: monitorBoard, database: database, directory: directory) }
        await MainActor.run {
            probe.start()
            monitorBoard.clearContents()
            monitorBoard.setString("monitored sample", forType: .string)
        }
        try await Task.sleep(for: .seconds(1.3))
        let monitored = await MainActor.run { probe.stop(); return probe.observed }
        try check(monitored && database.items().contains(where: { $0.text == "monitored sample" }), "monitor detects and persists changes")
        try database.clearHistory()

        let file = directory.appendingPathComponent("sample.txt")
        try Data("sample".utf8).write(to: file)
        board.clearContents()
        board.writeObjects([file as NSURL])
        let fileItem = ClipboardCapture.read(from: board, directory: directory, captureImages: true, captureFiles: true, sourceApp: "Finder")
        try check(fileItem?.kind == .file && fileItem?.filePaths == [file.path], "file reference capture")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1), atX: 0, y: 0)
        let image = NSImage(size: NSSize(width: 32, height: 24))
        image.addRepresentation(bitmap)
        board.clearContents()
        board.writeObjects([image])
        let imageItem = ClipboardCapture.read(from: board, directory: directory, captureImages: true, captureFiles: false, sourceApp: "Test App")
        try check(imageItem?.kind == .image && imageItem?.imageWidth == 32 && imageItem?.imageHeight == 24, "image capture")
        try check(imageItem?.thumbnailPath.map { FileManager.default.fileExists(atPath: $0) } == true, "image thumbnail")
        try check(imageItem?.displayTitle == "Image from Test App", "legacy image title fallback")
        if let tiff = image.tiffRepresentation {
            let namedImage = NSPasteboardItem()
            namedImage.setData(tiff, forType: .tiff)
            namedImage.setString(#"<img src="photo.png" alt="A &amp; B portrait">"#, forType: .html)
            board.clearContents()
            board.writeObjects([namedImage])
            let captured = ClipboardCapture.read(from: board, directory: directory, captureImages: true, captureFiles: false,
                                                 sourceApp: "Test App", sourceBundleID: "org.example.test")
            try check(captured?.kind == .image && captured?.title == "A & B portrait"
                      && captured?.sourceBundleID == "org.example.test", "image capture with browser title")
        } else { throw SmokeFailure.check("image TIFF fixture") }
        board.clearContents()
        board.setString(#"<img src="photo.png" alt="A &amp; B portrait">"#, forType: .html)
        try check(ClipboardCapture.imageTitle(from: board) == "A & B portrait", "image HTML title")
        board.clearContents()
        board.setString("https://example.com/photos/sunset-view.jpg", forType: NSPasteboard.PasteboardType("public.url"))
        try check(ClipboardCapture.imageTitle(from: board) == "sunset view", "image URL filename")

        let collection = ClipCollection(name: "Work")
        try database.save(collection)
        try check(database.collections().first?.name == "Work", "collection persistence")
        let secret = SecureItem(title: "Saved Secret", category: "API key", sourceApp: "Test App", sourceBundleID: "org.example.test")
        try database.save(secret)
        try check(database.secrets().first?.title == "Saved Secret" && database.secrets().first?.sourceApp == "Test App"
                  && database.secrets().first?.sourceBundleID == "org.example.test", "secret metadata persistence")
        let legacySecret = SecureItem(title: "Older Secret", category: "Secret")
        let legacyData = try JSONEncoder().encode(legacySecret)
        try check(try JSONDecoder().decode(SecureItem.self, from: legacyData).sourceApp == nil, "older secret decoding")
        try database.deleteSecret(secret.id)

        let benchmarkItems = (0..<10_001).map { index in
            ClipboardItem(kind: .text, title: "Benchmark item \(index)", text: "Benchmark content \(index)", contentHash: "benchmark-\(index)")
        }
        try database.saveItems(benchmarkItems)
        let loaded = database.items()
        try check(loaded.count == 10_001, "large history persistence")
        try check(loaded.contains(where: { $0.text == "Benchmark content 10000" }), "large history retrieval")
        try await MainActor.run {
            let model = try AppModel(database: database, startMonitoring: false, performCleanup: false)
            for size in [100, 1_000, 5_000, 10_001] {
                model.items = Array(loaded.prefix(size))
                let start = Date()
                let matches = model.filteredItems(query: "benchmark content", selection: .all)
                try check(matches.count == size, "search at \(size) items")
                try check(Date().timeIntervalSince(start) < 1.0, "search responsiveness at \(size) items")
            }
            model.addCollection(name: "New Project")
            guard let collection = model.collections.first(where: { $0.name == "New Project" }), let first = model.items.first else {
                throw SmokeFailure.check("collection creation")
            }
            model.toggleCollection(first, id: collection.id)
            try check(model.filteredItems(query: "New Project", selection: .all).contains(where: { $0.id == first.id }), "collection search")
            model.toggleFavorite(first)
            try check(model.filteredItems(query: "", selection: .favorites).contains(where: { $0.id == first.id }), "favorite filter")
            model.deleteCollection(collection)
            try check(!model.collections.contains(where: { $0.id == collection.id }), "collection deletion")

            guard let fileItem else { throw SmokeFailure.check("search fixture file") }
            model.items = [item, fileItem]
            model.secrets = [SecureItem(title: "Saved Secret", category: "API key", sourceApp: "Password App")]
            let finderResults = SearchBrowser.results(model: model, query: "", category: .recent,
                                                      filters: SearchFilters(sourceApp: "Finder"))
            try check(finderResults.count == 1 && finderResults[0].sourceApp == "Finder", "source filtering")
            let passwordResults = SearchBrowser.results(model: model, query: "", category: .passwords, filters: SearchFilters())
            try check(passwordResults.count == 1 && passwordResults[0].sourceApp == "Password App", "masked password search metadata")
            if let imageItem {
                model.items.append(imageItem)
                model.renameItem(imageItem, to: "Portrait")
                try check(model.items.contains(where: { $0.id == imageItem.id && $0.title == "Portrait" })
                          && database.items().contains(where: { $0.id == imageItem.id && $0.title == "Portrait" }),
                          "image rename persistence")
            }
        }

        let testID = UUID()
        defer { KeychainService.delete(id: testID) }
        try KeychainService.store("synthetic-test-value", id: testID)
        let retrieved = try await KeychainService.retrieve(id: testID, authenticate: false)
        try check(retrieved == "synthetic-test-value", "Keychain round trip")
        print("Smoke checks passed: classification, live change detection, text/file/image capture and titles, thumbnails, 10,001-item persistence and search, collection/source/password filters, Keychain")
    }

    private static func check(_ condition: Bool, _ name: String) throws {
        if !condition { throw SmokeFailure.check(name) }
    }
}

@MainActor final class MonitorProbe {
    private var monitor: ClipboardMonitor!
    private let database: Database
    private let directory: URL
    var observed = false

    init(board: NSPasteboard, database: Database, directory: URL) {
        self.database = database
        self.directory = directory
        monitor = ClipboardMonitor(pasteboard: board) { [weak self] board, _ in
            guard let self, let item = ClipboardCapture.read(from: board, directory: directory, captureImages: false, captureFiles: false, sourceApp: "Test App") else { return }
            try? database.save(item)
            observed = true
        }
    }

    func start() { monitor.start() }
    func stop() { monitor.stop() }
}
