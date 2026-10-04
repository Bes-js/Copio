import Foundation
import SQLite3

final class Database {
    private var db: OpaquePointer?
    let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory override: URL? = nil) throws {
        directory = override ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipCollections", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("history.sqlite3").path
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw DatabaseError.open }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA secure_delete=ON")
        try execute("CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, copied REAL NOT NULL, hash TEXT NOT NULL, searchable TEXT NOT NULL, payload BLOB NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_copied ON items(copied DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_hash ON items(hash)")
        try execute("CREATE TABLE IF NOT EXISTS collections (id TEXT PRIMARY KEY, sort_order INTEGER NOT NULL, payload BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS secrets (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
    }

    deinit { sqlite3_close(db) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.query }
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw DatabaseError.query }
        return stmt
    }

    private func bind(_ value: String, to index: Int32, in stmt: OpaquePointer) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, index, value, -1, transient)
    }

    private func bind(_ data: Data, to index: Int32, in stmt: OpaquePointer) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        data.withUnsafeBytes { buffer in
            _ = sqlite3_bind_blob(stmt, index, buffer.baseAddress, Int32(data.count), transient)
        }
    }

    private func decoded<T: Decodable>(_ type: T.Type, at index: Int32, from stmt: OpaquePointer) -> T? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, index)))
        return try? decoder.decode(T.self, from: data)
    }

    func save(_ item: ClipboardItem) throws {
        let stmt = try statement("INSERT OR REPLACE INTO items VALUES (?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(stmt) }
        bind(item.id.uuidString, to: 1, in: stmt)
        sqlite3_bind_double(stmt, 2, item.copiedAt.timeIntervalSince1970)
        bind(item.contentHash, to: 3, in: stmt)
        bind(([item.title, item.text ?? "", item.sourceApp ?? ""] + item.filePaths).joined(separator: " ").lowercased(), to: 4, in: stmt)
        bind(try encoder.encode(item), to: 5, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.query }
    }

    func saveItems(_ items: [ClipboardItem]) throws {
        guard !items.isEmpty else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for item in items { try save(item) }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func items() -> [ClipboardItem] {
        guard let stmt = try? statement("SELECT payload FROM items ORDER BY copied DESC") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = decoded(ClipboardItem.self, at: 0, from: stmt) { result.append(item) }
        }
        return result
    }

    func deleteItem(_ id: UUID) throws {
        let stmt = try statement("DELETE FROM items WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id.uuidString, to: 1, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.query }
    }

    func deleteItems(_ ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let stmt = try statement("DELETE FROM items WHERE id=?")
            defer { sqlite3_finalize(stmt) }
            for id in ids {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                bind(id.uuidString, to: 1, in: stmt)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.query }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func purgeDeletedContent() {
        // Discard older WAL frames after a history item is moved to Keychain.
        _ = sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
    }

    func clearHistory() throws { try execute("DELETE FROM items") }

    func resetAll() throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("DELETE FROM items")
            try execute("DELETE FROM collections")
            try execute("DELETE FROM secrets")
            try execute("COMMIT")
            purgeDeletedContent()
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func save(_ collection: ClipCollection) throws {
        let stmt = try statement("INSERT OR REPLACE INTO collections VALUES (?, ?, ?)")
        defer { sqlite3_finalize(stmt) }
        bind(collection.id.uuidString, to: 1, in: stmt)
        sqlite3_bind_int(stmt, 2, Int32(collection.sortOrder))
        bind(try encoder.encode(collection), to: 3, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.query }
    }

    func collections() -> [ClipCollection] {
        guard let stmt = try? statement("SELECT payload FROM collections ORDER BY sort_order, id") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [ClipCollection] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let collection = decoded(ClipCollection.self, at: 0, from: stmt) { result.append(collection) }
        }
        return result
    }

    func deleteCollection(_ id: UUID) throws {
        let stmt = try statement("DELETE FROM collections WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id.uuidString, to: 1, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.query }
    }

    func save(_ secret: SecureItem) throws {
        let stmt = try statement("INSERT OR REPLACE INTO secrets VALUES (?, ?)")
        defer { sqlite3_finalize(stmt) }
        bind(secret.id.uuidString, to: 1, in: stmt)
        bind(try encoder.encode(secret), to: 2, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.query }
    }

    func secrets() -> [SecureItem] {
        guard let stmt = try? statement("SELECT payload FROM secrets") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [SecureItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let secret = decoded(SecureItem.self, at: 0, from: stmt) { result.append(secret) }
        }
        return result
    }

    func deleteSecret(_ id: UUID) throws {
        let stmt = try statement("DELETE FROM secrets WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id.uuidString, to: 1, in: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.query }
    }
}

enum DatabaseError: LocalizedError {
    case open, query
    var errorDescription: String? { self == .open ? "Could not open the local database." : "Could not update the local database." }
}
