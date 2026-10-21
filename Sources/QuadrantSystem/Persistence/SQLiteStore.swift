import Foundation
import GRDB
import QuadrantCore

/// SQLite-backed `StateStore` and `UsageLog` (Data-Model › Persisted).
/// All writes run inside one GRDB transaction; a throwing mutation rolls the whole batch back.
public final class SQLiteStore: StateStore, UsageLog {
    private let queue: DatabaseQueue

    /// True when the database file was unreadable at open time and was replaced by a fresh one.
    /// The UI shows 「状态已重置」 once when this is set.
    public let didResetAfterCorruption: Bool

    /// The file the store was opened on.
    public let url: URL

    /// `~/Library/Application Support/QuadrantLauncher/state.sqlite`
    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuadrantLauncher", isDirectory: true)
            .appendingPathComponent("state.sqlite")
    }

    /// Opens (creating when needed) the database at `url` and migrates it.
    /// A file that is not a valid database is renamed to `state.corrupt-<timestamp>.sqlite` next to it,
    /// then a fresh database is created.
    public init(url: URL = SQLiteStore.defaultURL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.url = url

        do {
            queue = try Self.open(url)
            didResetAfterCorruption = false
        } catch let error as DatabaseError where Self.isCorruption(error) {
            try Self.moveAside(url)
            queue = try Self.open(url)
            didResetAfterCorruption = true
        }
    }

    // MARK: Open, migrate, recover

    private static func open(_ url: URL) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)
        return queue
    }

    private static func isCorruption(_ error: DatabaseError) -> Bool {
        error.resultCode == .SQLITE_NOTADB || error.resultCode == .SQLITE_CORRUPT
            || error.extendedResultCode == .SQLITE_NOTADB || error.extendedResultCode == .SQLITE_CORRUPT
    }

    private static func moveAside(_ url: URL) throws {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = url.deletingLastPathComponent()
        var target = dir.appendingPathComponent("state.corrupt-\(stamp).sqlite")
        var n = 1
        while fm.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("state.corrupt-\(stamp)-\(n).sqlite")
            n += 1
        }
        try fm.moveItem(at: url, to: target)
        // Stale journal files would be misread against the fresh database.
        for suffix in ["-wal", "-shm", "-journal"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            if fm.fileExists(atPath: side.path) { try? fm.removeItem(at: side) }
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-initial") { db in
            try db.create(table: "root_folder") { t in
                t.primaryKey("quadrant", .text)
                t.column("path", .text)
            }
            for edge in Edge.allCases {
                try db.execute(sql: "INSERT INTO root_folder (quadrant, path) VALUES (?, NULL)", arguments: [edge.rawValue])
            }
            try db.create(table: "folder_mark") { t in
                t.primaryKey("path", .text)
                t.column("mark", .text).notNull()
                t.column("marked_at", .double).notNull()
            }
            try db.create(table: "focus") { t in
                t.primaryKey("root_path", .text)
                t.column("branch_path", .text).notNull()
            }
            try db.create(table: "drill_path") { t in
                t.primaryKey("l3_path", .text)
                t.column("deep_path", .text).notNull()
            }
            try db.create(table: "stash_item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("target_path", .text).notNull().unique()
                t.column("kind", .text).notNull()
                t.column("added_at", .double).notNull()
            }
            try db.create(table: "pinned_slot") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("edge", .text).notNull()
                t.column("target_path", .text).notNull()
                t.column("added_at", .double).notNull()
                t.uniqueKey(["edge", "target_path"])
            }
            try db.create(table: "usage_event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull()
                t.column("action", .text).notNull()
                t.column("occurred_at", .double).notNull()
            }
            try db.create(index: "usage_event_path", on: "usage_event", columns: ["path"])
        }
        return migrator
    }

    // MARK: StateStore

    public func load() throws -> PersistentState {
        try queue.read { db in
            var state = PersistentState()

            for row in try Row.fetchAll(db, sql: "SELECT quadrant, path FROM root_folder") {
                let quadrant: String = row["quadrant"]
                let path: String? = row["path"]
                if let edge = Edge(rawValue: quadrant), let path {
                    state.roots[edge] = NodePath(path)
                }
            }
            for row in try Row.fetchAll(db, sql: "SELECT path, mark, marked_at FROM folder_mark") {
                let path = NodePath(row["path"] as String)
                guard let mark = FolderMark(rawValue: row["mark"]) else { continue }
                state.marks[path] = MarkRecord(path: path, mark: mark, markedAt: Self.date(row["marked_at"]))
            }
            for row in try Row.fetchAll(db, sql: "SELECT root_path, branch_path FROM focus") {
                state.focus[NodePath(row["root_path"] as String)] = NodePath(row["branch_path"] as String)
            }
            for row in try Row.fetchAll(db, sql: "SELECT l3_path, deep_path FROM drill_path") {
                state.drillPaths[NodePath(row["l3_path"] as String)] = NodePath(row["deep_path"] as String)
            }
            for row in try Row.fetchAll(db, sql: "SELECT target_path, kind, added_at FROM stash_item ORDER BY id") {
                guard let kind = NodeKind(rawValue: row["kind"]) else { continue }
                state.stash.append(StashItem(
                    targetPath: NodePath(row["target_path"] as String), kind: kind, addedAt: Self.date(row["added_at"])))
            }
            for row in try Row.fetchAll(db, sql: "SELECT edge, target_path, added_at FROM pinned_slot ORDER BY id") {
                guard let edge = Edge(rawValue: row["edge"]) else { continue }
                state.pinnedSlots.append(PinnedSlot(
                    edge: edge, targetPath: NodePath(row["target_path"] as String), addedAt: Self.date(row["added_at"])))
            }
            return state
        }
    }

    public func apply(_ mutations: [StateMutation]) throws {
        guard !mutations.isEmpty else { return }
        try queue.write { db in
            for mutation in mutations {
                try Self.apply(mutation, in: db)
            }
        }
    }

    private static func apply(_ mutation: StateMutation, in db: Database) throws {
        switch mutation {
        case .setRoot(let edge, let path):
            try db.execute(
                sql: "UPDATE root_folder SET path = ? WHERE quadrant = ?",
                arguments: [path?.raw, edge.rawValue])
        case .setMark(let record):
            try db.execute(
                sql: "INSERT OR REPLACE INTO folder_mark (path, mark, marked_at) VALUES (?, ?, ?)",
                arguments: [record.path.raw, record.mark.rawValue, record.markedAt.timeIntervalSince1970])
        case .clearMark(let path):
            try db.execute(sql: "DELETE FROM folder_mark WHERE path = ?", arguments: [path.raw])
        case .setFocus(let root, let branch):
            try db.execute(
                sql: "INSERT OR REPLACE INTO focus (root_path, branch_path) VALUES (?, ?)",
                arguments: [root.raw, branch.raw])
        case .setDrillPath(let l3, let deep):
            try db.execute(
                sql: "INSERT OR REPLACE INTO drill_path (l3_path, deep_path) VALUES (?, ?)",
                arguments: [l3.raw, deep.raw])
        case .setStash(let items):
            try db.execute(sql: "DELETE FROM stash_item")
            for item in items {
                try db.execute(
                    sql: "INSERT INTO stash_item (target_path, kind, added_at) VALUES (?, ?, ?)",
                    arguments: [item.targetPath.raw, item.kind.rawValue, item.addedAt.timeIntervalSince1970])
            }
        case .setPinnedSlots(let edge, let slots):
            try db.execute(sql: "DELETE FROM pinned_slot WHERE edge = ?", arguments: [edge.rawValue])
            for slot in slots {
                try db.execute(
                    sql: "INSERT INTO pinned_slot (edge, target_path, added_at) VALUES (?, ?, ?)",
                    arguments: [edge.rawValue, slot.targetPath.raw, slot.addedAt.timeIntervalSince1970])
            }
        }
    }

    // MARK: UsageLog

    public func all() throws -> [UsageEvent] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT path, action, occurred_at FROM usage_event ORDER BY id").compactMap { row in
                guard let action = UsageAction(rawValue: row["action"]) else { return nil }
                return UsageEvent(
                    path: NodePath(row["path"] as String), action: action, occurredAt: Self.date(row["occurred_at"]))
            }
        }
    }

    public func append(_ event: UsageEvent) throws {
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO usage_event (path, action, occurred_at) VALUES (?, ?, ?)",
                arguments: [event.path.raw, event.action.rawValue, event.occurredAt.timeIntervalSince1970])
        }
    }

    private static func date(_ interval: Double) -> Date {
        Date(timeIntervalSince1970: interval)
    }
}
