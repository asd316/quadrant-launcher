import Foundation

// Output of `Projection.project`. UI only draws these; all ordering and truncation happens in Core.

public struct BranchItem: Hashable, Sendable {
    public var path: NodePath
    public var name: String
    public var weight: Double
    public var isPinned: Bool
    public var isFocused: Bool
}

public struct BranchesResult: Hashable, Sendable {
    /// Rank order: pinned first (by markedAt ascending), then by weight descending. `items[0]` is the most important.
    public var items: [BranchItem]
    /// "+n": visible branches that did not fit (R2.3).
    public var truncatedCount: Int
    /// Hidden branches, for the "show all" entry (R3.1). They never consume capacity.
    public var hiddenCount: Int

    /// Layout order from the quadrant's leading end to its trailing end (left to right on top/bottom edges,
    /// top to bottom on left/right edges), with rank 0 in the middle (R2.1) and the others alternating outward.
    /// Example: 4 items give ranks [2,0,1,3]; 6 items give [4,2,0,1,3,5] (see `CenterOut.arrange`).
    /// UI places `visualOrder[k]` in the k-th slot along the edge and does no sorting of its own.
    public var visualOrder: [BranchItem] { CenterOut.arrange(items) }
}

public struct StarItem: Hashable, Sendable {
    public var path: NodePath
    public var name: String
    /// 0.25...1.
    public var brightness: Double
    public var isPinned: Bool
    public var hasDrillPath: Bool
    /// L3 folders under a branch are folders; a level-1 root can spread its direct files as file points (R2.8).
    public var kind: NodeKind = .folder
}

public struct StarsResult: Hashable, Sendable {
    /// The focused branch these stars belong to; in root-file mode, the root folder (R2.2, R2.8).
    public var branch: NodePath?
    /// Rank order: pinned first, then weight descending.
    public var items: [StarItem]
    public var truncatedCount: Int
    /// True when `items` are the direct files of the root folder, not L3 folders under `branch` (R2.8).
    public var isRootFiles: Bool = false

    public static let empty = StarsResult(branch: nil, items: [], truncatedCount: 0)
}

public struct FloatingItem: Hashable, Sendable {
    public var path: NodePath
    public var name: String
}

public struct FloatingResult: Hashable, Sendable {
    /// Top files by weight (max `Capacity.floatingSlots`).
    public var items: [FloatingItem]
    public var truncatedCount: Int

    public static let empty = FloatingResult(items: [], truncatedCount: 0)
}

public struct PinnedSlotItem: Hashable, Sendable {
    public var path: NodePath
    public var name: String
    public var isBroken: Bool
}

public enum EdgeStatus: Hashable, Sendable {
    /// No root folder configured.
    case empty
    /// A root folder is configured but no snapshot is available (R6.3, shown as "失效" by UI).
    case rootUnavailable
    case ready
}

public struct EdgeProjection: Hashable, Sendable {
    public var edge: Edge
    public var root: NodePath?
    public var status: EdgeStatus
    public var branches: BranchesResult
    public var stars: StarsResult
    public var floating: FloatingResult
    /// Folder the floating slots show. It stays on the last folder opened in the lens after the lens closes,
    /// so its "+n" can open that same folder (R2.6).
    public var currentFolder: NodePath? = nil
    public var pinnedSlots: [PinnedSlotItem]

    public var isEmpty: Bool { status == .empty }
}

/// Per-edge inputs that come from System and UI rather than from `PersistentState`.
public struct EdgeInput: Sendable {
    public var snapshot: FolderSnapshot?
    /// Number of named stars that fit, measured by UI.
    public var starCapacity: Int
    /// Folder whose direct files fill floating slots. nil means none.
    public var currentFolder: NodePath?
    /// Direct children of `currentFolder` when it is deeper than the snapshot (L4+, from the lens cache).
    /// When nil, children are looked up in the snapshot.
    public var currentFolderChildren: [FolderNode]?

    public init(
        snapshot: FolderSnapshot?, starCapacity: Int, currentFolder: NodePath? = nil,
        currentFolderChildren: [FolderNode]? = nil
    ) {
        self.snapshot = snapshot
        self.starCapacity = starCapacity
        self.currentFolder = currentFolder
        self.currentFolderChildren = currentFolderChildren
    }
}

/// Center-out arrangement used for branches (R2.1).
public enum CenterOut {
    /// Takes items in rank order and returns them in slot order, rank 0 at index `(n-1)/2`,
    /// then ranks alternate right, left, right ... around it. Example n=4: ranks [2,0,1,3]; n=6: [4,2,0,1,3,5].
    public static func arrange<T>(_ ranked: [T]) -> [T] {
        let n = ranked.count
        guard n > 1 else { return ranked }
        let center = (n - 1) / 2
        var slots = [T?](repeating: nil, count: n)
        var placed = 0
        var offset = 0
        while placed < n {
            for index in offset == 0 ? [center] : [center + offset, center - offset] where slots.indices.contains(index) {
                slots[index] = ranked[placed]
                placed += 1
            }
            offset += 1
        }
        return slots.compactMap { $0 }
    }
}
