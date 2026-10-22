import Foundation
import QuadrantCore

// Contract between QuadrantUI and QuadrantApp.
// The App builds a `PanelRenderModel` from Core state after every change; the UI only draws it
// and reports what the user did as `UIEvent`. All ranking, truncation and rule checks stay in Core.

/// Everything the panel draws, already decided by Core.
public struct PanelRenderModel: Equatable, Sendable {
    /// One entry per configured edge. A missing edge is an empty quadrant.
    public var quadrants: [Edge: EdgeProjection]
    public var stash: [StashSlot]
    /// Present while the lens is open (browsing a folder or showing filter results).
    public var lens: LensModel?
    public var filterText: String
    public var keyboardRegion: KeyboardRegion
    /// The node the keyboard selection is on, if any.
    public var keyboardSelection: NodePath?
    /// R7.2: during a drag only the stash is drawn.
    public var isHalfHidden: Bool
    /// R8.7: fraction 0...1 while a copy-to runs.
    public var copyProgress: Double?
    /// One-line message shown near the stash (rejections and notices, already worded).
    public var message: String?

    public init(
        quadrants: [Edge: EdgeProjection] = [:],
        stash: [StashSlot] = [],
        lens: LensModel? = nil,
        filterText: String = "",
        keyboardRegion: KeyboardRegion = .center,
        keyboardSelection: NodePath? = nil,
        isHalfHidden: Bool = false,
        copyProgress: Double? = nil,
        message: String? = nil
    ) {
        self.quadrants = quadrants
        self.stash = stash
        self.lens = lens
        self.filterText = filterText
        self.keyboardRegion = keyboardRegion
        self.keyboardSelection = keyboardSelection
        self.isHalfHidden = isHalfHidden
        self.copyProgress = copyProgress
        self.message = message
    }
}

public struct StashSlot: Equatable, Sendable, Identifiable {
    public var path: NodePath
    public var kind: NodeKind
    public var isBroken: Bool
    public var id: NodePath { path }

    public init(path: NodePath, kind: NodeKind, isBroken: Bool) {
        self.path = path
        self.kind = kind
        self.isBroken = isBroken
    }
}

public struct LensModel: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Browsing `crumbs.last`. `crumbs` runs from the root folder to the current folder.
        case folder(edge: Edge, crumbs: [NodePath])
        /// Showing filter matches across all quadrants.
        case filter(query: String)
    }

    public var mode: Mode
    public var rows: [LensRow]
    /// R2.4 large folders: rows read so far are shown, with 「正在读取…」 at the bottom.
    public var isLoading: Bool

    public init(mode: Mode, rows: [LensRow], isLoading: Bool = false) {
        self.mode = mode
        self.rows = rows
        self.isLoading = isLoading
    }
}

public struct LensRow: Equatable, Sendable, Identifiable {
    public var path: NodePath
    public var kind: NodeKind
    /// Filter mode only: the edge the match belongs to, shown as context.
    public var edge: Edge?
    public var id: NodePath { path }

    public init(path: NodePath, kind: NodeKind, edge: Edge? = nil) {
        self.path = path
        self.kind = kind
        self.edge = edge
    }
}

/// What the user did. The App turns these into Core intents (and System calls where needed).
public enum UIEvent: Sendable, Equatable {
    case clickBranch(Edge, NodePath)
    case clickStar(Edge, NodePath)
    /// Clicked a 「+n」: open the lens on `folder` to see everything.
    case openLens(Edge, folder: NodePath)
    /// Single click on a file or a lens row: move the keyboard selection there.
    case select(NodePath)
    /// Double click: files open with the default app, folders enter in the lens.
    case doubleClick(NodePath, NodeKind)
    case copyPath(NodePath)
    case lensEnter(NodePath)
    /// Tap on a crumb or the back chevron. `nil` means one level up.
    case lensBack(to: NodePath?)
    case stashRemove(NodePath)
    /// Hover-button or context-menu actions.
    case pinSlot(Edge, NodePath)
    case unpinSlot(Edge, NodePath)
    case hideBranch(Edge, NodePath)
    case showAllBranches(Edge)
    case pinFolder(Edge, NodePath)
    case unpinFolder(NodePath)
    case revealInFinder(NodePath)
    /// R7.2 / R7.3. The UI reports the outcome; the App resizes the window and informs Core.
    case dragBegan(NodePath, NodeKind)
    case dragEnded(DragOutcome)
    /// How many named stars fit in this edge's wedge at the current screen size (Data-Model › 展示上限).
    case starCapacityMeasured(Edge, Int)
}

/// Places that accept a drop during a drag (R7.2–R7.4). While half-hidden the main panel is transparent
/// and click-through; the App shows one small window per zone, each hosting `DropZoneView`.
public enum DropZone: Hashable, Sendable {
    case stash
    case pinnedShelf(Edge)
}
