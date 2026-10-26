import Foundation

// Shared vocabulary for every layer: the domain terms (Branch, Star, Lens, Stash, slots, Drill Path)
// and the persisted tables and fields.

/// Standardized absolute POSIX path without a trailing slash. Every state is keyed by path, never by quadrant.
public struct NodePath: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) {
        var standardized = (raw as NSString).expandingTildeInPath
        standardized = (standardized as NSString).standardizingPath
        while standardized.count > 1 && standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        self.raw = standardized
    }

    public var name: String { (raw as NSString).lastPathComponent }
    public var parent: NodePath? { raw == "/" ? nil : NodePath((raw as NSString).deletingLastPathComponent) }
    public var description: String { raw }

    public func appending(_ component: String) -> NodePath {
        NodePath((raw as NSString).appendingPathComponent(component))
    }

    /// True when `self` is a strict ancestor of `other`.
    public func isAncestor(of other: NodePath) -> Bool {
        other.raw.hasPrefix(raw == "/" ? "/" : raw + "/") && other != self
    }

    public static func < (lhs: NodePath, rhs: NodePath) -> Bool { lhs.raw < rhs.raw }
}

public enum NodeKind: String, Sendable, Codable {
    case file
    case folder
}

/// Quadrant position. A pinned slot belongs to the edge of the same name.
public enum Edge: String, Sendable, Codable, CaseIterable {
    case top
    case bottom
    case left
    case right

    public var isHorizontalSide: Bool { self == .left || self == .right }
}

/// One node of a scanned folder tree. Files have no children.
public struct FolderNode: Hashable, Sendable {
    public var path: NodePath
    public var kind: NodeKind
    public var modifiedAt: Date
    /// File size in bytes; nil for folders (shown in the lens).
    public var size: Int64?
    public var isSymlink: Bool
    public var children: [FolderNode]

    public init(
        path: NodePath, kind: NodeKind, modifiedAt: Date, size: Int64? = nil, isSymlink: Bool = false,
        children: [FolderNode] = []
    ) {
        self.path = path
        self.kind = kind
        self.modifiedAt = modifiedAt
        self.size = size
        self.isSymlink = isSymlink
        self.children = children
    }

    public var name: String { path.name }
    public var folders: [FolderNode] { children.filter { $0.kind == .folder } }
    public var files: [FolderNode] { children.filter { $0.kind == .file } }
}

/// In-memory tree of one root folder: L1 (root), L2 (branches), L3 (stars), plus each folder's direct files.
/// L4 and deeper are read on demand through `FolderSource.children(of:)`.
public struct FolderSnapshot: Hashable, Sendable {
    public var root: FolderNode

    public init(root: FolderNode) {
        self.root = root
    }

    public func node(at path: NodePath) -> FolderNode? {
        func find(_ node: FolderNode) -> FolderNode? {
            if node.path == path { return node }
            guard node.path.isAncestor(of: path) else { return nil }
            for child in node.children {
                if let hit = find(child) { return hit }
            }
            return nil
        }
        return find(root)
    }
}

/// Usage actions from R1.1 and R8.8. Raw values are the `usage_event.action` column values.
public enum UsageAction: String, Sendable, Codable, CaseIterable {
    case focusBranch = "focus_branch"
    case openStar = "open_star"
    case enterFolder = "enter_folder"
    case copyPath = "copy_path"
    case dragOut = "drag_out"
    case open = "open"
    case stash = "stash"
    /// R8.8: recorded on the destination folder.
    case copyTo = "copy_to"
}

public struct UsageEvent: Hashable, Sendable, Codable {
    public var path: NodePath
    public var action: UsageAction
    public var occurredAt: Date

    public init(path: NodePath, action: UsageAction, occurredAt: Date) {
        self.path = path
        self.action = action
        self.occurredAt = occurredAt
    }
}

public enum FolderMark: String, Sendable, Codable {
    case hidden
    case pinned
}

/// One row of `folder_mark`. One mark per path, so hidden and pinned exclude each other (R3.4).
public struct MarkRecord: Hashable, Sendable, Codable {
    public var path: NodePath
    public var mark: FolderMark
    public var markedAt: Date

    public init(path: NodePath, mark: FolderMark, markedAt: Date) {
        self.path = path
        self.mark = mark
        self.markedAt = markedAt
    }
}

/// One row of `stash_item`. A path appears at most once in the stash.
public struct StashItem: Hashable, Sendable, Codable {
    public var targetPath: NodePath
    public var kind: NodeKind
    public var addedAt: Date

    public init(targetPath: NodePath, kind: NodeKind, addedAt: Date) {
        self.targetPath = targetPath
        self.kind = kind
        self.addedAt = addedAt
    }
}

/// One row of `pinned_slot`. Slots follow the edge, not the root folder. A path appears at most once per edge.
public struct PinnedSlot: Hashable, Sendable, Codable {
    public var edge: Edge
    public var targetPath: NodePath
    public var addedAt: Date

    public init(edge: Edge, targetPath: NodePath, addedAt: Date) {
        self.edge = edge
        self.targetPath = targetPath
        self.addedAt = addedAt
    }
}

/// Everything persisted in SQLite except usage events.
public struct PersistentState: Hashable, Sendable {
    /// Root folder per quadrant. A missing key means the quadrant is empty.
    public var roots: [Edge: NodePath]
    public var marks: [NodePath: MarkRecord]
    /// Focused branch, keyed by root folder path (R5.1, R5.3).
    public var focus: [NodePath: NodePath]
    /// Drill path, keyed by L3 folder path (R5.2).
    public var drillPaths: [NodePath: NodePath]
    /// Oldest first.
    public var stash: [StashItem]
    /// Oldest first within each edge.
    public var pinnedSlots: [PinnedSlot]

    public init(
        roots: [Edge: NodePath] = [:],
        marks: [NodePath: MarkRecord] = [:],
        focus: [NodePath: NodePath] = [:],
        drillPaths: [NodePath: NodePath] = [:],
        stash: [StashItem] = [],
        pinnedSlots: [PinnedSlot] = []
    ) {
        self.roots = roots
        self.marks = marks
        self.focus = focus
        self.drillPaths = drillPaths
        self.stash = stash
        self.pinnedSlots = pinnedSlots
    }
}

/// Fixed display capacities (R2.1, R2.5, R4.1, R4.3). Starfield capacity is measured by the UI and passed in.
public enum Capacity {
    public static func branches(on edge: Edge) -> Int { edge.isHorizontalSide ? 6 : 4 }
    public static let floatingSlots = 5
    public static let pinnedSlotsPerEdge = 5
    public static let stashItems = 3
}

/// A write the System layer persists. Core emits these; it never writes itself.
public enum StateMutation: Hashable, Sendable {
    case setRoot(Edge, NodePath?)
    case setMark(MarkRecord)
    case clearMark(NodePath)
    case setFocus(root: NodePath, branch: NodePath)
    case setDrillPath(l3: NodePath, deep: NodePath)
    /// Replaces the whole stash, oldest first.
    case setStash([StashItem])
    /// Replaces all pinned slots of one edge, oldest first.
    case setPinnedSlots(Edge, [PinnedSlot])
}

// MARK: - Ports implemented by QuadrantSystem

public protocol FolderSource: Sendable {
    /// Scans L1–L3 plus each folder's direct files.
    func snapshot(root: NodePath) async throws -> FolderSnapshot
    /// Direct children of one folder, for the lens at L4 and deeper.
    func children(of folder: NodePath) async throws -> [FolderNode]
    func exists(_ path: NodePath) -> Bool
    /// Emits the set of changed paths whenever something under `roots` changes on disk.
    func changes(under roots: [NodePath]) -> AsyncStream<Set<NodePath>>
}

public protocol StateStore: Sendable {
    func load() throws -> PersistentState
    func apply(_ mutations: [StateMutation]) throws
}

public protocol UsageLog: Sendable {
    func all() throws -> [UsageEvent]
    func append(_ event: UsageEvent) throws
}
