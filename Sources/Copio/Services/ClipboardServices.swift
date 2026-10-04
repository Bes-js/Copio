import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum ClassificationService {
    static func kind(for text: String, hasRichText: Bool) -> ItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["http", "https", "ftp"].contains(url.scheme?.lowercased() ?? ""), !trimmed.contains(where: \.isWhitespace) { return .url }
        let codeSignals = ["func ", "let ", "const ", "import ", "class ", "def ", "#!/", "</", "=>", "git ", "npm ", "SELECT "]
        if (trimmed.contains("\n") && codeSignals.contains(where: { trimmed.contains($0) })) || trimmed.hasPrefix("$ ") { return .code }
        return hasRichText ? .richText : .text
    }

    static func sensitiveCategory(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, trimmed.count <= 20_000 else { return nil }
        if trimmed.contains("-----BEGIN ") && trimmed.contains("PRIVATE KEY-----") { return "Private key" }
        let patterns: [(String, String)] = [
            (#"\bsk-(?:live|test)-[A-Za-z0-9]{16,}\b"#, "API key"),
            (#"\bgh[opusr]_[A-Za-z0-9_]{20,}\b"#, "Access token"),
            (#"\bBearer\s+[A-Za-z0-9._~+/-]{24,}\b"#, "Authentication token"),
            (#"(?i)(?:api[_ -]?key|secret[_ -]?key|access[_ -]?token|password)\s*[:=]\s*['\"]?\S{12,}"#, "Secret")
        ]
        for (pattern, category) in patterns where trimmed.range(of: pattern, options: .regularExpression) != nil { return category }
        if trimmed.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }) {
            let digits = trimmed.compactMap(\.wholeNumberValue)
            if (13...19).contains(digits.count) {
                let checksum = digits.reversed().enumerated().reduce(0) { sum, pair in
                    let value = pair.offset.isMultiple(of: 2) ? pair.element : pair.element * 2
                    return sum + (value > 9 ? value - 9 : value)
                }
                if checksum.isMultiple(of: 10) { return "Credit card-like data" }
            }
        }
        // A bare high-entropy string is too ambiguous to save or label automatically.
        return nil
    }
}

enum ClipboardCapture {
    static func read(from pasteboard: NSPasteboard, directory: URL, captureImages: Bool, captureFiles: Bool,
                     sourceApp: String?, sourceBundleID: String? = nil) -> ClipboardItem? {
        let types = pasteboard.types ?? []
        if captureFiles, types.contains(.fileURL) {
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            if !urls.isEmpty {
                let paths = urls.map(\.path)
                let title = paths.count == 1 ? urls[0].lastPathComponent : "\(paths.count) files"
                return ClipboardItem(kind: .file, title: title, filePaths: paths, contentHash: hash("file:" + paths.joined(separator: "\u{0}")),
                                     sourceApp: sourceApp, sourceBundleID: sourceBundleID)
            }
        }
        if captureImages, types.contains(.tiff) || types.contains(.png), let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let digest = hashData(png)
            let imageDirectory = directory.appendingPathComponent("Images", isDirectory: true)
            try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
            let original = imageDirectory.appendingPathComponent(digest + ".png")
            let thumb = imageDirectory.appendingPathComponent(digest + "-thumb.png")
            if !FileManager.default.fileExists(atPath: original.path) { try? png.write(to: original, options: .atomic) }
            if !FileManager.default.fileExists(atPath: thumb.path), let thumbnail = thumbnailData(from: png) {
                try? thumbnail.write(to: thumb, options: .atomic)
            }
            return ClipboardItem(kind: .image, title: imageTitle(from: pasteboard) ?? "Image", imagePath: original.path,
                                 thumbnailPath: thumb.path, contentHash: "image:" + digest,
                                 sourceApp: sourceApp, sourceBundleID: sourceBundleID,
                                 imageWidth: rep.pixelsWide, imageHeight: rep.pixelsHigh, byteCount: png.count)
        }
        guard let content = pasteboard.string(forType: .string), !content.isEmpty else { return nil }
        let rich = types.contains(.rtf) || types.contains(.html)
        let kind = ClassificationService.kind(for: content, hasRichText: rich)
        let line = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? content
        let title = String(line.prefix(180))
        var item = ClipboardItem(kind: kind, title: title, text: content, contentHash: hash("text:" + content),
                                 sourceApp: sourceApp, sourceBundleID: sourceBundleID)
        if rich, let data = pasteboard.data(forType: .rtf) {
            let richDirectory = directory.appendingPathComponent("RichText", isDirectory: true)
            try? FileManager.default.createDirectory(at: richDirectory, withIntermediateDirectories: true)
            let path = richDirectory.appendingPathComponent(item.contentHash + ".rtf")
            if !FileManager.default.fileExists(atPath: path.path) { try? data.write(to: path, options: .atomic) }
            item.richTextPath = path.path
        }
        return item
    }

    static func imageTitle(from pasteboard: NSPasteboard) -> String? {
        if let html = pasteboard.string(forType: .html) {
            let sample = String(html.prefix(50_000))
            let pattern = #"<img\b[^>]*\b(?:alt|title)\s*=\s*["']([^"']{1,180})["']"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: sample, range: NSRange(sample.startIndex..., in: sample)),
               let range = Range(match.range(at: 1), in: sample),
               let title = cleanImageTitle(String(sample[range])) {
                return title
            }
        }
        if let rawURL = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url")),
           let url = URL(string: rawURL), ["png", "jpg", "jpeg", "webp", "gif", "heic", "avif"].contains(url.pathExtension.lowercased()) {
            let fileName = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? url.deletingPathExtension().lastPathComponent
            return cleanImageTitle(fileName.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "))
        }
        return nil
    }

    private static func cleanImageTitle(_ raw: String) -> String? {
        let decoded = raw.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard decoded.count >= 3, !["image", "photo", "picture"].contains(decoded.lowercased()) else { return nil }
        return String(decoded.prefix(120))
    }

    private static func thumbnailData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func hash(_ value: String) -> String { hashData(Data(value.utf8)) }
    private static func hashData(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

@MainActor final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let pasteboard: NSPasteboard
    private var activationObserver: NSObjectProtocol?
    private var activeBundleIDs: Set<String> = []
    private let onChange: (NSPasteboard, Set<String>) -> Void

    init(pasteboard: NSPasteboard = .general, onChange: @escaping (NSPasteboard, Set<String>) -> Void) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        activeBundleIDs = Set([NSWorkspace.shared.frontmostApplication?.bundleIdentifier].compactMap { $0 })
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let id = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if let id { self?.activeBundleIDs.insert(id) }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.2
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func tick() {
        let board = pasteboard
        if let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { activeBundleIDs.insert(current) }
        let candidates = activeBundleIDs
        activeBundleIDs = Set([NSWorkspace.shared.frontmostApplication?.bundleIdentifier].compactMap { $0 })
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        onChange(board, candidates)
    }

    func skipCurrentChange() { lastChangeCount = pasteboard.changeCount }
}

enum PasteService {
    static func write(_ item: ClipboardItem) -> Bool {
        let board = NSPasteboard.general
        switch item.kind {
        case .image:
            guard let path = item.imagePath, let image = NSImage(contentsOfFile: path) else { return false }
            board.clearContents()
            return board.writeObjects([image])
        case .file:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return false }
            board.clearContents()
            return board.writeObjects(urls as [NSURL])
        default:
            guard let text = item.text else { return false }
            board.clearContents()
            if let path = item.richTextPath, let rtf = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                board.setData(rtf, forType: .rtf)
            }
            return board.setString(text, forType: .string)
        }
    }

    static func paste(to application: NSRunningApplication?) -> Bool {
        guard let application, AXIsProcessTrusted() else { return false }
        guard application.activate() else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else { return }
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
        return true
    }
}
