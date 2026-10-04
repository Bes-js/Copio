import Foundation
import SwiftUI

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case text, url, code, image, file, richText, other
    var id: String { rawValue }
    var title: String { switch self { case .richText: "Rich text"; default: rawValue.capitalized } }
    var symbol: String { switch self {
    case .text: "text.alignleft"; case .url: "link"; case .code: "chevron.left.forwardslash.chevron.right"
    case .image: "photo"; case .file: "doc"; case .richText: "textformat"; case .other: "square.on.square"
    } }
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: ItemKind
    var title: String
    var text: String? = nil
    var imagePath: String? = nil
    var thumbnailPath: String? = nil
    var filePaths: [String] = []
    var richTextPath: String? = nil
    var contentHash: String
    var createdAt: Date = .now
    var copiedAt: Date = .now
    var sourceApp: String? = nil
    var sourceBundleID: String? = nil
    var isFavorite: Bool = false
    var collectionIDs: Set<UUID> = []
    var imageWidth: Int? = nil
    var imageHeight: Int? = nil
    var byteCount: Int? = nil

    var displayTitle: String {
        guard kind == .image, title == "Image" else { return title }
        if let sourceApp, !sourceApp.isEmpty { return "Image from \(sourceApp)" }
        if let imageWidth, let imageHeight { return "Image \(imageWidth) × \(imageHeight)" }
        return "Image"
    }

    var subtitle: String {
        switch kind {
        case .image: return [imageWidth, imageHeight].compactMap { $0 }.count == 2 ? "\(imageWidth!) × \(imageHeight!)" : "Image"
        case .file: return filePaths.count == 1 ? URL(fileURLWithPath: filePaths[0]).pathExtension.uppercased() + " file" : "\(filePaths.count) files"
        default: return kind.title
        }
    }
}

struct ClipCollection: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "folder"
    var color: String = "blue"
    var isFavorite: Bool = false
    var sortOrder: Int = 0
    var tint: Color {
        switch color {
        case "green": .green; case "orange": .orange; case "purple": .purple
        case "pink": .pink; case "gray": .gray; default: .blue
        }
    }
}

struct SecureItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var category: String
    var createdAt: Date = .now
    var lastUsedAt: Date? = nil
    var sourceApp: String? = nil
    var sourceBundleID: String? = nil
}

enum SidebarSelection: Hashable {
    case all, favorites, images, urls, code, files, secure, collection(UUID), smart(String)
}

enum HistoryLimit: Int, CaseIterable, Identifiable {
    case ten = 10, twentyFive = 25, fifty = 50, hundred = 100, twoFifty = 250
    case fiveHundred = 500, thousand = 1000, fiveThousand = 5000, unlimited = 0
    var id: Int { rawValue }
    var label: String { self == .unlimited ? "Unlimited" : rawValue.formatted() }
}
