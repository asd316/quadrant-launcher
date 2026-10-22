import Foundation
import QuadrantCore
import QuadrantUI

/// Where a node sits in the panel. The keyboard selection is App-side state; this resolves it against the render model.
enum NodeRole: Equatable {
    case branch(Edge)
    case star(Edge)
    case lensRow
    case floating(Edge)
    case pinnedSlot(Edge)
    case stash
}

struct SelectedNode: Equatable {
    var path: NodePath
    var kind: NodeKind
    var role: NodeRole
}

enum Selection {
    /// Finds `path` in what the panel currently shows. Lens rows win over quadrant content.
    static func find(_ path: NodePath, in model: PanelRenderModel) -> SelectedNode? {
        if let row = model.lens?.rows.first(where: { $0.path == path }) {
            return SelectedNode(path: path, kind: row.kind, role: .lensRow)
        }
        for edge in Edge.allCases {
            guard let q = model.quadrants[edge] else { continue }
            if q.branches.items.contains(where: { $0.path == path }) {
                return SelectedNode(path: path, kind: .folder, role: .branch(edge))
            }
            if q.stars.items.contains(where: { $0.path == path }) {
                return SelectedNode(path: path, kind: .folder, role: .star(edge))
            }
            if q.floating.items.contains(where: { $0.path == path }) {
                return SelectedNode(path: path, kind: .file, role: .floating(edge))
            }
            if q.pinnedSlots.contains(where: { $0.path == path }) {
                return SelectedNode(path: path, kind: .file, role: .pinnedSlot(edge))
            }
        }
        if let slot = model.stash.first(where: { $0.path == path }) {
            return SelectedNode(path: path, kind: slot.kind, role: .stash)
        }
        return nil
    }

    /// The nodes ↑/↓ walk through: lens rows while the lens is open, otherwise the keyboard region's content.
    static func order(in model: PanelRenderModel) -> [NodePath] {
        if let lens = model.lens { return lens.rows.map(\.path) }
        let edge: Edge
        switch model.keyboardRegion {
        case .center: return model.stash.map(\.path)
        case .top: edge = .top
        case .bottom: edge = .bottom
        case .left: edge = .left
        case .right: edge = .right
        }
        guard let q = model.quadrants[edge] else { return [] }
        return q.branches.items.map(\.path) + q.stars.items.map(\.path)
            + q.floating.items.map(\.path) + q.pinnedSlots.map(\.path)
    }

    /// Next selection for ↑ (`-1`) or ↓ (`+1`). Clamps at both ends; with no selection ↓ takes the first, ↑ the last.
    static func move(from current: NodePath?, by step: Int, in model: PanelRenderModel) -> NodePath? {
        let list = order(in: model)
        guard !list.isEmpty else { return nil }
        guard let current, let index = list.firstIndex(of: current) else {
            return step > 0 ? list.first : list.last
        }
        return list[min(max(index + step, 0), list.count - 1)]
    }

    /// The quadrant an action on `node` belongs to (pin target, edge of a lens row).
    static func edge(of node: SelectedNode, in model: PanelRenderModel) -> Edge? {
        switch node.role {
        case .branch(let e), .star(let e), .floating(let e), .pinnedSlot(let e):
            return e
        case .lensRow:
            switch model.lens?.mode {
            case .folder(let edge, _): return edge
            case .filter: return model.lens?.rows.first(where: { $0.path == node.path })?.edge
            case nil: return nil
            }
        case .stash:
            return regionEdge(model.keyboardRegion)
        }
    }

    static func regionEdge(_ region: KeyboardRegion) -> Edge? {
        switch region {
        case .center: nil
        case .top: .top
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        }
    }

    /// R8.2–R8.4: a folder shown in a quadrant or the lens receives the copy, everything else goes to the stash.
    static func pasteTarget(for node: SelectedNode?) -> PasteTarget {
        guard let node, node.kind == .folder else { return .stash }
        switch node.role {
        case .branch, .star, .lensRow: return .folder(node.path)
        case .floating, .pinnedSlot, .stash: return .stash
        }
    }
}
