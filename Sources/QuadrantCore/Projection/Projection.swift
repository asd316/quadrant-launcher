import Foundation

/// `project(状态, 快照, 使用分, 展示上限) → 每个象限要显示什么` (Data-Model › Projection output).
/// Pure and synchronous. Implements R1.4, R2.1–R2.3, R2.5, R3.1–R3.3.
public enum Projection {
    /// - Parameters:
    ///   - inputs: per-edge snapshot, star capacity and current folder. A missing edge is treated as no snapshot.
    ///   - usage: built with the same `now`.
    ///   - exists: disk existence check, used only for pinned slots not found in the snapshot (R6.1).
    public static func project(
        state: PersistentState,
        inputs: [Edge: EdgeInput],
        usage: UsageIndex,
        now: Date,
        exists: (NodePath) -> Bool
    ) -> [Edge: EdgeProjection] {
        var result: [Edge: EdgeProjection] = [:]
        for edge in Edge.allCases {
            result[edge] = project(
                edge: edge, state: state,
                input: inputs[edge] ?? EdgeInput(snapshot: nil, starCapacity: 0),
                usage: usage, now: now, exists: exists)
        }
        return result
    }

    public static func project(
        edge: Edge,
        state: PersistentState,
        input: EdgeInput,
        usage: UsageIndex,
        now: Date,
        exists: (NodePath) -> Bool
    ) -> EdgeProjection {
        guard let root = state.roots[edge] else {
            // Empty quadrant: nothing is drawn, so pinned slots are not projected either.
            return EdgeProjection(
                edge: edge, root: nil, status: .empty, branches: emptyBranches, stars: .empty,
                floating: .empty, pinnedSlots: [])
        }
        let pinnedSlots = projectPinnedSlots(edge: edge, state: state, snapshot: input.snapshot, exists: exists)
        guard let snapshot = input.snapshot else {
            return EdgeProjection(
                edge: edge, root: root, status: .rootUnavailable, branches: emptyBranches, stars: .empty,
                floating: .empty, pinnedSlots: pinnedSlots)
        }
        let focus = state.focus[root]
        let branches = projectBranches(edge: edge, snapshot: snapshot, state: state, focus: focus, usage: usage, now: now)
        return EdgeProjection(
            edge: edge, root: root, status: .ready,
            branches: branches,
            stars: projectStars(
                snapshot: snapshot, state: state, focus: focus, currentFolder: input.currentFolder,
                currentFolderChildren: input.currentFolderChildren, capacity: input.starCapacity,
                usage: usage, now: now),
            floating: projectFloating(input: input, usage: usage, now: now),
            currentFolder: input.currentFolder,
            pinnedSlots: pinnedSlots)
    }

    private static let emptyBranches = BranchesResult(items: [], truncatedCount: 0, hiddenCount: 0)

    // MARK: Branches (R2.1, R2.3, R3.1, R3.2)

    static func projectBranches(
        edge: Edge, snapshot: FolderSnapshot, state: PersistentState, focus: NodePath?,
        usage: UsageIndex, now: Date
    ) -> BranchesResult {
        let capacity = Capacity.branches(on: edge)
        let all = snapshot.root.folders
        let hiddenCount = all.filter { state.marks[$0.path]?.mark == .hidden }.count
        let visible = all.filter { state.marks[$0.path]?.mark != .hidden }
        let (pinned, rest) = DisplayWeight.splitPinned(visible, marks: state.marks)
        let shownPinned = Array(pinned.prefix(capacity))
        let room = capacity - shownPinned.count
        let rankedRest = DisplayWeight.rank(rest, usage: usage, now: now).prefix(room)

        let items =
            shownPinned.map { item($0, isPinned: true, focus: focus, usage: usage, now: now) }
            + rankedRest.map { item($0.node, isPinned: false, focus: focus, usage: usage, now: now) }
        return BranchesResult(items: items, truncatedCount: visible.count - items.count, hiddenCount: hiddenCount)
    }

    private static func item(
        _ node: FolderNode, isPinned: Bool, focus: NodePath?, usage: UsageIndex, now: Date
    ) -> BranchItem {
        BranchItem(
            path: node.path, name: node.name,
            weight: DisplayWeight.weight(of: node, usage: usage, now: now),
            isPinned: isPinned, isFocused: node.path == focus)
    }

    // MARK: Stars / cloud (R2.2, R2.3, R2.8, R3.2)

    static func projectStars(
        snapshot: FolderSnapshot, state: PersistentState, focus: NodePath?, currentFolder: NodePath?,
        currentFolderChildren: [FolderNode]?, capacity: Int, usage: UsageIndex, now: Date
    ) -> StarsResult {
        guard let cloud = currentFolder ?? focus else { return .empty }
        if state.marks[cloud]?.mark == .hidden { return .empty }
        let root = snapshot.root.path
        // L1 and L2 children are complete in the snapshot; L3 and deeper need the lens/cloud cache.
        let children: [FolderNode]?
        if let currentFolderChildren {
            children = currentFolderChildren
        } else if cloud == root {
            children = snapshot.root.children
        } else if depth(of: cloud, below: root) == 1 {
            children = snapshot.node(at: cloud)?.children
        } else {
            children = nil
        }
        guard let children else {
            return StarsResult(branch: cloud, items: [], truncatedCount: 0, isLoading: true)
        }
        return cloudStars(children, cloud: cloud, root: root, state: state, capacity: capacity, usage: usage, now: now)
    }

    /// R2.8: folders and files of one folder share the star cloud. Pinned folders first, then everything by
    /// weight; files are leaves, folders drill one level deeper.
    static func cloudStars(
        _ children: [FolderNode], cloud: NodePath, root: NodePath, state: PersistentState,
        capacity: Int, usage: UsageIndex, now: Date
    ) -> StarsResult {
        let visible = children.filter { state.marks[$0.path]?.mark != .hidden }
        let folders = visible.filter { $0.kind == .folder }
        let files = visible.filter { $0.kind == .file }
        let (pinned, restFolders) = DisplayWeight.splitPinned(folders, marks: state.marks)
        let rankedRest = DisplayWeight.rank(restFolders + files, usage: usage, now: now)
        let capacity = max(0, capacity)
        let shownPinned = Array(pinned.prefix(capacity))
        let shownRest = rankedRest.prefix(capacity - shownPinned.count)
        let maxWeight = visible.map { DisplayWeight.weight(of: $0, usage: usage, now: now) }.max() ?? 0
        let childDepth = depth(of: cloud, below: root) + 1

        func star(_ node: FolderNode, isPinned: Bool) -> StarItem {
            StarItem(
                path: node.path, name: node.name,
                brightness: DisplayWeight.brightness(
                    weight: DisplayWeight.weight(of: node, usage: usage, now: now), maxWeight: maxWeight),
                isPinned: isPinned, hasDrillPath: state.drillPaths[node.path] != nil, kind: node.kind,
                canPin: node.kind == .folder && childDepth <= 2)
        }
        let items = shownPinned.map { star($0, isPinned: true) }
            + shownRest.map { star($0.node, isPinned: false) }
        return StarsResult(branch: cloud, items: items, truncatedCount: visible.count - items.count)
    }

    /// Levels below `root`: root itself is 0, a branch is 1, an L3 folder is 2.
    static func depth(of folder: NodePath, below root: NodePath) -> Int {
        guard folder != root, root.isAncestor(of: folder) else { return 0 }
        let rel = folder.raw.dropFirst(root.raw == "/" ? 1 : root.raw.count + 1)
        return rel.split(separator: "/").count
    }

    // MARK: Floating slots (R2.5)

    static func projectFloating(input: EdgeInput, usage: UsageIndex, now: Date) -> FloatingResult {
        guard let current = input.currentFolder else { return .empty }
        let children: [FolderNode]
        if let provided = input.currentFolderChildren {
            children = provided
        } else if let node = input.snapshot?.node(at: current), node.kind == .folder {
            children = node.children
        } else {
            return .empty
        }
        let files = children.filter { $0.kind == .file }
        let top = DisplayWeight.rank(files, usage: usage, now: now).prefix(Capacity.floatingSlots)
        return FloatingResult(
            items: top.map { FloatingItem(path: $0.node.path, name: $0.node.name) },
            truncatedCount: files.count - top.count)
    }

    // MARK: Pinned slots (R4.3, R6.1)

    static func projectPinnedSlots(
        edge: Edge, state: PersistentState, snapshot: FolderSnapshot?, exists: (NodePath) -> Bool
    ) -> [PinnedSlotItem] {
        state.pinnedSlots
            .filter { $0.edge == edge }
            .sorted { $0.addedAt < $1.addedAt }
            .prefix(Capacity.pinnedSlotsPerEdge)
            .map { slot in
                // Found in the snapshot: valid. Otherwise it may just be deeper than the snapshot, so ask the disk.
                let broken = snapshot?.node(at: slot.targetPath) == nil && !exists(slot.targetPath)
                return PinnedSlotItem(path: slot.targetPath, name: slot.targetPath.name, isBroken: broken)
            }
    }
}
