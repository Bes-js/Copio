import Foundation

struct ClipArchive: Codable {
    let version: Int
    let exportedAt: Date
    let items: [ClipboardItem]
    let collections: [ClipCollection]
}
