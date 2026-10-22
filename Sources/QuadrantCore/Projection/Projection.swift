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
                snapshot: snapshot, state: state, focus: focus, capacity: input.starCapacity, usage: usage, now: now),
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

    // MARK: Stars (R2.2, R2.3, R3.2)

    static func projectStars(
        snapshot: FolderSnapshot, state: PersistentState, focus: NodePath?, capacity: Int,
        usage: UsageIndex, now: Date
    ) -> StarsResult {
        guard let focus,
            let branch = snapshot.root.folders.first(where: { $0.path == focus }),
            state.marks[focus]?.mark != .hidden
        else { return .empty }

        let groups = branch.folders
        // Brightness is relative to the strongest star of the whole group, shown or not.
        let maxWeight = groups.map { DisplayWeight.weight(of: $0, usage: usage, now: now) }.max() ?? 0
        let capacity = max(0, capacity)
        let (pinned, rest) = DisplayWeight.splitPinned(groups, marks: state.marks)
        let shownPinned = Array(pinned.prefix(capacity))
        let rankedRest = DisplayWeight.rank(rest, usage: usage, now: now).prefix(capacity - shownPinned.count)

        func star(_ node: FolderNode, isPinned: Bool) -> StarItem {
            StarItem(
                path: node.path, name: node.name,
                brightness: DisplayWeight.brightness(
                    weight: DisplayWeight.weight(of: node, usage: usage, now: now), maxWeight: maxWeight),
                isPinned: isPinned, hasDrillPath: state.drillPaths[node.path] != nil)
        }
        let items = shownPinned.map { star($0, isPinned: true) } + rankedRest.map { star($0.node, isPinned: false) }
        return StarsResult(branch: focus, items: items, truncatedCount: groups.count - items.count)
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
