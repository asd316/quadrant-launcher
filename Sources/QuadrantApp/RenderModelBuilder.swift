import Foundation
import QuadrantCore
import QuadrantUI

/// Everything needed to build the panel's render model. Pure data in, pure data out.
struct RenderInputs {
    var state: PanelState
    var snapshots: [Edge: FolderSnapshot]
    var starCapacity: [Edge: Int]
    /// Direct children of folders read through `FolderSource.children(of:)`.
    var childrenCache: [NodePath: [FolderNode]]
    var usage: UsageIndex
    var now: Date
    var exists: PathExistence
    var selection: NodePath?
    var copyProgress: Double?
    var message: String?
}

enum RenderModelBuilder {
    static func build(_ input: RenderInputs) -> PanelRenderModel {
        let state = input.state
        var edgeInputs: [Edge: EdgeInput] = [:]
        for edge in Edge.allCases {
            guard let root = state.persistent.roots[edge] else { continue }
            let (folder, children) = currentFolder(edge: edge, root: root, input: input)
            edgeInputs[edge] = EdgeInput(
                snapshot: input.snapshots[edge], starCapacity: input.starCapacity[edge] ?? 0,
                currentFolder: folder, currentFolderChildren: children)
        }
        let exists = input.exists
        let quadrants = Projection.project(
            state: state.persistent, inputs: edgeInputs, usage: input.usage, now: input.now,
            exists: { exists.exists($0) })

        let stash = state.persistent.stash.map { item in
            StashSlot(path: item.targetPath, kind: item.kind, isBroken: !exists.exists(item.targetPath))
        }
        return PanelRenderModel(
            quadrants: quadrants,
            stash: stash,
            lens: lens(input),
            filterText: state.filterText,
            keyboardRegion: state.region,
            keyboardSelection: input.selection,
            isHalfHidden: state.display == .halfHidden,
            copyProgress: state.copies.isEmpty ? nil : (input.copyProgress ?? 0),
            message: input.message)
    }

    /// Floating slots follow the lens folder of this quadrant while the lens is open there, else the focused branch.
    private static func currentFolder(
        edge: Edge, root: NodePath, input: RenderInputs
    ) -> (NodePath?, [FolderNode]?) {
        let lens = input.state.lens
        if lens.isOpen, lens.edge == edge, let folder = lens.folders[edge] {
            return (folder, input.childrenCache[folder])
        }
        return (input.state.persistent.focus[root], nil)
    }

    private static func lens(_ input: RenderInputs) -> LensModel? {
        let state = input.state
        if !state.filterText.isEmpty {
            let matches = Filter.matches(state.filterText, in: input.snapshots, usage: input.usage, now: input.now)
            return LensModel(
                mode: .filter(query: state.filterText),
                rows: matches.map { LensRow(
                    path: $0.node.path, kind: $0.node.kind, edge: $0.edge,
                    modifiedAt: $0.node.modifiedAt, size: $0.node.size) })
        }
        guard state.lens.isOpen, let edge = state.lens.edge, let folder = state.lens.folders[edge],
              let root = state.persistent.roots[edge]
        else { return nil }

        let children: [FolderNode]?
        if let cached = input.childrenCache[folder] {
            children = cached
        } else if depth(of: folder, below: root) <= 1, let node = input.snapshots[edge]?.node(at: folder) {
            // Snapshot holds complete children for the root and its branches; a star (third level) holds files only.
            children = node.children
        } else {
            children = nil
        }
        let rows = DisplayWeight.rank(children ?? [], usage: input.usage, now: input.now)
            .map { LensRow(path: $0.node.path, kind: $0.node.kind, modifiedAt: $0.node.modifiedAt, size: $0.node.size) }
        return LensModel(
            mode: .folder(edge: edge, crumbs: crumbs(root: root, folder: folder)),
            rows: rows, isLoading: children == nil)
    }

    /// Levels below the root: the root itself is 0.
    static func depth(of folder: NodePath, below root: NodePath) -> Int {
        guard folder != root, root.isAncestor(of: folder) else { return 0 }
        let rel = folder.raw.dropFirst(root.raw == "/" ? 1 : root.raw.count + 1)
        return rel.split(separator: "/").count
    }

    /// Root to folder, both included. A folder outside the root yields just itself.
    static func crumbs(root: NodePath, folder: NodePath) -> [NodePath] {
        var chain = [folder]
        var cursor = folder
        while cursor != root {
            guard let parent = cursor.parent, root == parent || root.isAncestor(of: parent) else { return [folder] }
            chain.append(parent)
            cursor = parent
        }
        return chain.reversed()
    }
}
