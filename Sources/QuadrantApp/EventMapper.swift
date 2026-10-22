import Foundation
import QuadrantCore
import QuadrantUI

/// What the App does for one user action: feed Core, or handle it itself.
enum AppCommand {
    case intent(Intent)
    /// Keyboard selection is App-side state.
    case select(NodePath?)
    case reveal(NodePath)
    /// R7.7: open a folder in Finder with the panel stepping behind it (no close).
    case openFolderInFinder(NodePath)
    case starCapacity(Edge, Int)
}

/// Read-only view of the current state, enough to map events without touching AppKit.
struct MappingContext {
    var state: PanelState
    var model: PanelRenderModel
    var starCapacity: [Edge: Int]
    var exists: PathExistence
    /// Kind of an existing path, nil when it does not exist.
    var kindOf: @Sendable (NodePath) -> NodeKind? = FileKinds.kind(of:)
}

enum FileKinds {
    static func kind(of path: NodePath) -> NodeKind? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.raw, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? .folder : .file
    }
}

/// `UIEvent → [AppCommand]` (User-Flow, Data-Model › 用户意图). Pure.
enum EventMapper {
    static func commands(for event: UIEvent, in ctx: MappingContext) -> [AppCommand] {
        switch event {
        case .clickBranch(let edge, let path):
            return [.intent(.focusBranch(edge, branch: path))]
        case .clickStar(let edge, let path):
            return [.intent(.clickStar(edge, star: path, existence: ctx.exists))]
        case .openLens(let edge, let folder):
            return [.intent(.openLens(edge, folder: folder))]
        case .select(let path):
            return [.select(path)]
        case .doubleClick(let path, let kind):
            // R7.6: a file opens with its app and the panel closes. R7.7: a folder opens in Finder, panel steps behind.
            return kind == .file ? [.intent(.open(path))] : [.openFolderInFinder(path)]
        case .externalDrop(let paths, let zone):
            return externalDrop(paths, on: zone, in: ctx)
        case .copyPath(let path):
            return [.intent(.copyPath(path))]
        case .lensEnter(let path):
            return [.intent(.lensEnter(path))]
        case .backgroundClicked:
            // R7.5: one click outside the lens is the lens-level Esc, never the panel-level one.
            guard ctx.state.lens.isOpen else { return [] }
            if !ctx.state.filterText.isEmpty {
                return [.intent(.setFilter("")), .intent(.dismissLens)]
            }
            return [.intent(.dismissLens)]
        case .lensBack(let target):
            return lensBack(to: target, in: ctx)
        case .stashRemove(let path):
            return [.intent(.stashRemove(path))]
        case .pinSlot(let edge, let path):
            return [.intent(.pinSlot(edge, path, kind: .file))]
        case .unpinSlot(let edge, let path):
            return [.intent(.unpinSlot(edge, path))]
        case .hideBranch(_, let path):
            return [.intent(.hide(path))]
        case .showAllBranches(let edge):
            return showAllBranches(edge, in: ctx)
        case .pinFolder(let edge, let path):
            return [.intent(.pin(path, region: pinRegion(edge: edge, folder: path, in: ctx)))]
        case .unpinFolder(let path):
            return [.intent(.unpin(path))]
        case .revealInFinder(let path):
            return [.reveal(path)]
        case .dragBegan(let path, let kind):
            return [.intent(.beginDrag(path, kind: kind))]
        case .dragEnded(let outcome):
            return [.intent(.endDrag(outcome))]
        case .starCapacityMeasured(let edge, let count):
            return [.starCapacity(edge, count)]
        }
    }

    /// R7.7: files dragged in from Finder. Missing paths are skipped.
    static func externalDrop(_ paths: [NodePath], on zone: DropZone, in ctx: MappingContext) -> [AppCommand] {
        paths.compactMap { path in
            guard let kind = ctx.kindOf(path) else { return nil }
            switch zone {
            case .stash: return .intent(.stashAdd(path, kind: kind))
            case .pinnedShelf(let edge): return .intent(.pinSlot(edge, path, kind: kind))
            }
        }
    }

    /// Enter a folder in the lens; when the lens is closed, open it on that folder in the quadrant that owns it.
    static func enterFolder(_ folder: NodePath, in ctx: MappingContext) -> [AppCommand] {
        if ctx.state.lens.isOpen, ctx.state.lens.edge != nil, ctx.state.filterText.isEmpty {
            return [.intent(.lensEnter(folder))]
        }
        guard let edge = owningEdge(of: folder, in: ctx) else { return [] }
        // A filter result lens has to give way to the folder lens.
        let clearFilter: [AppCommand] = ctx.state.filterText.isEmpty ? [] : [.intent(.setFilter(""))]
        return clearFilter + [.intent(.openLens(edge, folder: folder))]
    }

    static func owningEdge(of path: NodePath, in ctx: MappingContext) -> Edge? {
        if case .filter = ctx.model.lens?.mode,
           let edge = ctx.model.lens?.rows.first(where: { $0.path == path })?.edge { return edge }
        if let edge = ctx.state.lens.edge, ctx.state.lens.isOpen { return edge }
        return Edge.allCases.first { edge in
            guard let root = ctx.state.persistent.roots[edge] else { return false }
            return root == path || root.isAncestor(of: path)
        }
    }

    /// Tapping a crumb: repeat "back" until the lens stands on it. Core stops at the lens floor.
    static func lensBack(to target: NodePath?, in ctx: MappingContext) -> [AppCommand] {
        guard let target else { return [.intent(.lensBack)] }
        guard let edge = ctx.state.lens.edge, let current = ctx.state.lens.folders[edge],
              target != current, target.isAncestor(of: current)
        else { return [] }
        let steps = depth(current) - depth(target)
        return Array(repeating: .intent(.lensBack), count: steps)
    }

    private static func depth(_ path: NodePath) -> Int {
        path.raw.split(separator: "/").count
    }

    /// R3.1: every hidden branch of the quadrant's root comes back.
    static func showAllBranches(_ edge: Edge, in ctx: MappingContext) -> [AppCommand] {
        guard let root = ctx.state.persistent.roots[edge] else { return [] }
        return ctx.state.persistent.marks.values
            .filter { $0.mark == .hidden && $0.path.parent == root }
            .sorted { $0.path < $1.path }
            .map { .intent(.unhide($0.path)) }
    }

    /// R3.3: branches count against the branch capacity, stars against the measured star capacity.
    static func pinRegion(edge: Edge, folder: NodePath, in ctx: MappingContext) -> PinRegion {
        let projection = ctx.model.quadrants[edge]
        if let root = ctx.state.persistent.roots[edge], folder.parent == root {
            return PinRegion(
                pinnedCount: projection?.branches.items.filter(\.isPinned).count ?? 0,
                capacity: Capacity.branches(on: edge))
        }
        return PinRegion(
            pinnedCount: projection?.stars.items.filter(\.isPinned).count ?? 0,
            capacity: ctx.starCapacity[edge] ?? 0)
    }
}
