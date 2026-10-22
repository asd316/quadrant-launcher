import Foundation

// Types of the Core state machine. See docs/03-tech-design/Data-Model（数据结构与接口契约）.md "Contracts".
// Rules: Domain-Model R1.1, R3–R8.

public enum PanelDisplay: Hashable, Sendable {
    case closed
    case full
    case halfHidden
}

/// Where the keyboard is. Remembered across close and reopen (Design-Principles › Cross navigation).
public enum KeyboardRegion: Hashable, Sendable {
    case center
    case top
    case bottom
    case left
    case right

    public init(_ edge: Edge) {
        switch edge {
        case .top: self = .top
        case .bottom: self = .bottom
        case .left: self = .left
        case .right: self = .right
        }
    }
}

public enum Direction: Hashable, Sendable {
    case up
    case down
    case left
    case right

    var edge: Edge {
        switch self {
        case .up: .top
        case .down: .bottom
        case .left: .left
        case .right: .right
        }
    }
}

/// The lens (detail overlay) and where each quadrant currently stands in it.
public struct LensState: Hashable, Sendable {
    public var isOpen = false
    /// Quadrant the lens was opened from. Nil while a filter result lens is not tied to one quadrant.
    public var edge: Edge?
    /// Current folder per quadrant. Floor of "back" is `floor`.
    public var folders: [Edge: NodePath] = [:]
    /// Topmost folder the lens may go back to (the star, or the folder behind "+n").
    public var floor: NodePath?
    /// Set when the lens was opened from an L3 star: drill path (R5.2) is recorded under this key.
    public var l3: NodePath?

    public init() {}
}

/// The part of the panel that R7.3 must restore after a drag.
public struct PanelSnapshot: Hashable, Sendable {
    public var lens: LensState
    public var filterText: String
    public var lensOpenBeforeFilter: Bool?
    public var region: KeyboardRegion
}

public struct DragSession: Hashable, Sendable {
    public var path: NodePath
    public var kind: NodeKind
    /// State before the drag started (R7.3).
    public var snapshot: PanelSnapshot
}

public struct PanelState: Hashable, Sendable {
    public var persistent: PersistentState
    public var display: PanelDisplay
    public var lens: LensState
    public var filterText: String
    /// Whether the lens was open before the user started typing; Esc restores it (User-Flow panel states).
    public var lensOpenBeforeFilter: Bool?
    public var region: KeyboardRegion
    /// Quadrants whose root folder was reported missing (R6.3). Reported, never auto-replaced.
    public var missingRoots: Set<Edge>
    public var drag: DragSession?
    /// Copy-to jobs the System is still running (R8.7); the UI shows progress at the center while non-empty.
    public var copies: [CopyJob]

    public init(
        persistent: PersistentState = PersistentState(),
        display: PanelDisplay = .closed,
        lens: LensState = LensState(),
        filterText: String = "",
        lensOpenBeforeFilter: Bool? = nil,
        region: KeyboardRegion = .center,
        missingRoots: Set<Edge> = [],
        drag: DragSession? = nil,
        copies: [CopyJob] = []
    ) {
        self.persistent = persistent
        self.display = display
        self.lens = lens
        self.filterText = filterText
        self.lensOpenBeforeFilter = lensOpenBeforeFilter
        self.region = region
        self.missingRoots = missingRoots
        self.drag = drag
        self.copies = copies
    }
}

/// A copy-to started by R8.2 and not yet reported finished (R8.7).
public struct CopyJob: Hashable, Sendable {
    public var sources: [NodePath]
    public var destination: NodePath
}

/// A node resolved by the App from the pasteboard (existing path plus its kind).
public struct PasteItem: Hashable, Sendable {
    public var path: NodePath
    public var kind: NodeKind
    public init(_ path: NodePath, kind: NodeKind) {
        self.path = path
        self.kind = kind
    }
}

/// Where a paste goes: the keyboard-selected quadrant folder (R8.2) or the stash (R8.3).
public enum PasteTarget: Hashable, Sendable {
    case folder(NodePath)
    case stash
}

/// System's report for a finished copy-to (R8.7).
public enum CopyResult: Hashable, Sendable {
    /// Names of the items created in the destination.
    case success(copiedNames: [String])
    /// Human-readable reason. System has already removed incomplete copies.
    case failure(reason: String)
}

/// Transient message shown in place (R8.7). Rejections are refusals; notices report outcomes.
public enum Notice: Hashable, Sendable {
    /// 「已复制到 <folder name>」
    case copiedTo(folderName: String)
    /// 「复制失败：<reason>」
    case copyFailed(reason: String)
}


/// Existence check the UI/System supplies so Core stays pure (R6.2). Defaults to "everything exists".
public struct PathExistence: Sendable {
    public let exists: @Sendable (NodePath) -> Bool
    public init(_ exists: @escaping @Sendable (NodePath) -> Bool) { self.exists = exists }
    public static let all = PathExistence { _ in true }
    public static func only(_ paths: Set<NodePath>) -> PathExistence { PathExistence { paths.contains($0) } }
}

/// Pin capacity of one display region (R3.3). Core cannot see the snapshot, so the caller counts.
public struct PinRegion: Hashable, Sendable {
    public var pinnedCount: Int
    public var capacity: Int
    public init(pinnedCount: Int, capacity: Int) {
        self.pinnedCount = pinnedCount
        self.capacity = capacity
    }
}

public enum DragOutcome: Hashable, Sendable {
    case otherApp
    case stash
    /// R7.3, R7.4: dropped on an edge's pinned section; files become pinned slots, folders are rejected.
    case pinnedShelf(Edge)
    case cancelled
    /// R7.4: dropping on another quadrant is not a valid target; treated as cancel.
    case quadrant(Edge)
}

/// UI → Core. One case per row of the Data-Model "用户意图" table.
///
/// Not covered: moving the keyboard selection with plain arrow keys inside a region. It needs
/// geometry (nearest node in a direction) that only the UI owns; the UI resolves the selection
/// and then sends the concrete intent (focusBranch, clickStar, copyPath, ...).
public enum Intent: Sendable {
    // Panel
    case summon
    case escape
    // Focus, stars, lens
    case focusBranch(Edge, branch: NodePath)
    case clickStar(Edge, star: NodePath, existence: PathExistence = .all)
    case openLens(Edge, folder: NodePath)
    case lensEnter(NodePath)
    case lensBack
    case dismissLens
    // Keyboard
    case setFilter(String)
    case crossNavigate(Direction)
    // Hand-off
    case copyPath(NodePath)
    case open(NodePath)
    case beginDrag(NodePath, kind: NodeKind)
    case endDrag(DragOutcome)
    // Keep at hand
    case stashAdd(NodePath, kind: NodeKind)
    case stashRemove(NodePath)
    case pinSlot(Edge, NodePath, kind: NodeKind)
    case unpinSlot(Edge, NodePath)
    // Marks
    case hide(NodePath)
    case unhide(NodePath)
    case pin(NodePath, region: PinRegion)
    case unpin(NodePath)
    // Roots
    case setRoot(Edge, NodePath?)
    case reportRootMissing(Edge, Bool)
    // Paste and copy (R8)
    /// R8.1: ⌘C on the selected node.
    case copyNode(NodePath, kind: NodeKind)
    /// R8.2-R8.4, R8.6: ⌘V. `items` are already resolved to existing paths by the App (empty = nothing usable).
    case paste(items: [PasteItem], target: PasteTarget)
    /// R8.7, R8.8: System reports a copy-to started by `Effect.copyTo`.
    case copyFinished(destination: NodePath, result: CopyResult)
}

public enum Rejection: Hashable, Sendable {
    /// R3.3: pins in the region already equal its display capacity.
    case pinsFull(capacity: Int)
    /// R4.3: the edge already holds 5 pinned slots.
    case pinnedSlotsFull(Edge, capacity: Int)
    /// R4.3 / R3.5: pinned slots hold files only.
    case pinnedSlotsFilesOnly
    /// R8.4: pasteboard holds no existing file or path. UI text: 剪贴板里没有可用的文件或路径
    case clipboardEmpty
    /// R8.6: destination is inside a source folder. UI text: 不能复制到它自己里面
    case copyIntoItself
}

/// Core → App. One case per row of the Data-Model "副作用" table.
public enum Effect: Hashable, Sendable {
    case recordUsage(UsageEvent)
    case persist([StateMutation])
    case copyToPasteboard(NodePath)
    case openWithDefaultApp(NodePath)
    case loadChildren(NodePath)
    case showRejection(Rejection)
    /// R8.7: outcome message (「已复制到 <name>」 / failure reason).
    case showNotice(Notice)
    /// R8.1: put the node on the pasteboard as file reference plus path text. Panel stays open.
    case writeNodeToPasteboard(NodePath, kind: NodeKind)
    /// R8.2: System copies in the background (R8.5 renaming, cleanup on failure), then sends `copyFinished`.
    case copyTo(sources: [NodePath], destination: NodePath)
    case closePanel
    case enterHalfHidden
    case restoreFull
}

extension PersistentState {
    /// Single place that defines what each mutation means, so Core state and System storage cannot drift.
    public mutating func apply(_ mutation: StateMutation) {
        switch mutation {
        case .setRoot(let edge, let path):
            roots[edge] = path
        case .setMark(let record):
            marks[record.path] = record
        case .clearMark(let path):
            marks[path] = nil
        case .setFocus(let root, let branch):
            focus[root] = branch
        case .setDrillPath(let l3, let deep):
            drillPaths[l3] = deep
        case .setStash(let items):
            stash = items
        case .setPinnedSlots(let edge, let slots):
            pinnedSlots = pinnedSlots.filter { $0.edge != edge } + slots
        }
    }
}
