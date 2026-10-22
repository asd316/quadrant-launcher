import Foundation

/// `reduce(state, intent, now) -> (new state, effects)`. Pure and synchronous (AGENTS.md › Layers).
public func reduce(_ state: PanelState, _ intent: Intent, now: Date) -> (PanelState, [Effect]) {
    var r = Reducer(state: state, now: now)
    r.handle(intent)
    return (r.state, r.effects)
}

private struct Reducer {
    var state: PanelState
    var effects: [Effect] = []
    let now: Date

    init(state: PanelState, now: Date) {
        self.state = state
        self.now = now
    }

    // MARK: Helpers

    mutating func persist(_ mutations: [StateMutation]) {
        guard !mutations.isEmpty else { return }
        for m in mutations { state.persistent.apply(m) }
        effects.append(.persist(mutations))
    }

    mutating func usage(_ path: NodePath, _ action: UsageAction) {
        effects.append(.recordUsage(UsageEvent(path: path, action: action, occurredAt: now)))
    }

    /// Closing resets the in-memory browse state. The keyboard region is kept (reopens where it left off).
    mutating func close() {
        state.display = .closed
        state.lens = LensState()
        state.filterText = ""
        state.lensOpenBeforeFilter = nil
        state.drag = nil
        effects.append(.closePanel)
    }

    var isFull: Bool { state.display == .full }

    mutating func clearFilter() {
        state.filterText = ""
        if let before = state.lensOpenBeforeFilter { state.lens.isOpen = before }
        state.lensOpenBeforeFilter = nil
        if !state.lens.isOpen { state.lens = LensState(folders: state.lens.folders) }
    }

    // MARK: Dispatch

    mutating func handle(_ intent: Intent) {
        switch intent {
        case .summon:
            guard state.display == .closed else { return }
            state.display = .full
            effects.append(.restoreFull)

        case .escape:
            guard isFull else { return }
            if !state.filterText.isEmpty {
                clearFilter()
            } else if state.lens.isOpen {
                closeLens()
            } else {
                close()
            }

        case .focusBranch(let edge, let branch):
            guard isFull, let root = state.persistent.roots[edge], !state.missingRoots.contains(edge) else { return }
            usage(branch, .focusBranch)
            persist([.setFocus(root: root, branch: branch)])
            // R2.6: the focused branch becomes the current folder, so floating slots leave the old lens folder.
            if !state.filterText.isEmpty { clearFilter() }
            if state.lens.isOpen, state.lens.edge == edge { closeLens() }
            state.lens.folders[edge] = branch

        case .clickStar(let edge, let star, let existence):
            guard isFull, state.persistent.roots[edge] != nil, !state.missingRoots.contains(edge) else { return }
            usage(star, .openStar)
            // R5.2 + R6.2: reopen where the user left off; fall back to the nearest existing ancestor.
            var target = star
            if let deep = state.persistent.drillPaths[star], star.isAncestor(of: deep) || deep == star {
                var candidate: NodePath? = deep
                while let c = candidate, c != star, !existence.exists(c) { candidate = c.parent }
                target = candidate ?? star
            }
            openLensState(edge: edge, folder: target, floor: star, l3: star)
            effects.append(.loadChildren(target))

        case .openLens(let edge, let folder):
            guard isFull else { return }
            if !state.filterText.isEmpty { clearFilter() }
            if let root = state.persistent.roots[edge], folder.parent == root {
                persist([.setFocus(root: root, branch: folder)])
            }
            openLensState(edge: edge, folder: folder, floor: folder, l3: nil)
            effects.append(.loadChildren(folder))

        case .drillCloud(let edge, let folder):
            guard isFull, let root = state.persistent.roots[edge], !state.missingRoots.contains(edge),
                  folder == root || root.isAncestor(of: folder)
            else { return }
            if !state.filterText.isEmpty { clearFilter() }
            if state.lens.isOpen { closeLens() }
            // An L2 branch also updates focus; deeper folders only move the cloud (R2.8).
            if folder != root {
                if folder.parent == root {
                    usage(folder, .focusBranch)
                    persist([.setFocus(root: root, branch: folder)])
                } else {
                    usage(folder, .enterFolder)
                }
            }
            state.lens.folders[edge] = folder
            effects.append(.loadChildren(folder))

        case .cloudUp(let edge):
            guard isFull, let root = state.persistent.roots[edge], !state.missingRoots.contains(edge),
                  let current = state.lens.folders[edge], current != root,
                  let parent = current.parent, parent == root || root.isAncestor(of: parent)
            else { return }
            if !state.filterText.isEmpty { clearFilter() }
            if state.lens.isOpen { closeLens() }
            if parent.parent == root {
                persist([.setFocus(root: root, branch: parent)])
            }
            state.lens.folders[edge] = parent
            effects.append(.loadChildren(parent))

        case .lensEnter(let folder):
            guard isFull, state.lens.isOpen, let edge = state.lens.edge else { return }
            if let root = state.persistent.roots[edge], folder.parent == root {
                persist([.setFocus(root: root, branch: folder)])
            }
            state.lens.folders[edge] = folder
            usage(folder, .enterFolder)
            recordDrill(folder)
            effects.append(.loadChildren(folder))

        case .lensBack:
            guard isFull, state.lens.isOpen, let edge = state.lens.edge,
                  let current = state.lens.folders[edge], let floor = state.lens.floor,
                  current != floor, let parent = current.parent, floor == parent || floor.isAncestor(of: parent)
            else { return }
            state.lens.folders[edge] = parent
            if let root = state.persistent.roots[edge], parent.parent == root {
                persist([.setFocus(root: root, branch: parent)])
            }
            recordDrill(parent)
            effects.append(.loadChildren(parent))

        case .dismissLens:
            guard isFull, state.lens.isOpen else { return }
            closeLens()

        case .setFilter(let text):
            guard isFull else { return }
            if state.filterText.isEmpty, !text.isEmpty {
                state.lensOpenBeforeFilter = state.lens.isOpen
                state.lens.isOpen = true
                state.filterText = text
            } else if text.isEmpty {
                clearFilter()
            } else {
                state.filterText = text
            }

        case .crossNavigate(let dir):
            guard isFull else { return }
            state.region = Self.jump(from: state.region, dir)

        case .copyPath(let path):
            guard isFull else { return }
            usage(path, .copyPath)
            effects.append(.copyToPasteboard(path))
            close() // R7.1

        case .open(let path):
            guard isFull else { return }
            usage(path, .open)
            effects.append(.openWithDefaultApp(path))
            close() // R7.6

        case .beginDrag(let path, let kind):
            guard isFull else { return }
            state.drag = DragSession(path: path, kind: kind, snapshot: PanelSnapshot(
                lens: state.lens, filterText: state.filterText,
                lensOpenBeforeFilter: state.lensOpenBeforeFilter, region: state.region))
            state.display = .halfHidden
            effects.append(.enterHalfHidden) // R7.2

        case .endDrag(let outcome):
            guard state.display == .halfHidden, let drag = state.drag else { return }
            switch outcome {
            case .otherApp:
                usage(drag.path, .dragOut)
                close()
            case .stash:
                stashAdd(drag.path, drag.kind)
                restore(drag.snapshot)
            case .pinnedShelf(let edge):
                restore(drag.snapshot)
                handle(.pinSlot(edge, drag.path, kind: drag.kind))
            case .cancelled, .quadrant:
                restore(drag.snapshot)
            }

        case .stashAdd(let path, let kind):
            stashAdd(path, kind)

        case .stashRemove(let path):
            let items = state.persistent.stash
            guard items.contains(where: { $0.targetPath == path }) else { return }
            persist([.setStash(items.filter { $0.targetPath != path })])

        case .pinSlot(let edge, let path, let kind):
            guard kind == .file else {
                effects.append(.showRejection(.pinnedSlotsFilesOnly))
                return
            }
            let slots = state.persistent.pinnedSlots.filter { $0.edge == edge }
            if slots.contains(where: { $0.targetPath == path }) { return }
            // R4.3 + R4.4: broken slots count too, so the count is just the stored rows.
            guard slots.count < Capacity.pinnedSlotsPerEdge else {
                effects.append(.showRejection(.pinnedSlotsFull(edge, capacity: Capacity.pinnedSlotsPerEdge)))
                return
            }
            persist([.setPinnedSlots(edge, slots + [PinnedSlot(edge: edge, targetPath: path, addedAt: now)])])

        case .unpinSlot(let edge, let path):
            let slots = state.persistent.pinnedSlots.filter { $0.edge == edge }
            guard slots.contains(where: { $0.targetPath == path }) else { return }
            persist([.setPinnedSlots(edge, slots.filter { $0.targetPath != path })])

        case .hide(let path):
            let current = state.persistent.marks[path]?.mark
            if current == .hidden { return }
            var ms: [StateMutation] = []
            if current == .pinned { ms.append(.clearMark(path)) } // R3.4: unpin first
            ms.append(.setMark(MarkRecord(path: path, mark: .hidden, markedAt: now)))
            persist(ms)

        case .unhide(let path):
            guard state.persistent.marks[path]?.mark == .hidden else { return }
            persist([.clearMark(path)])

        case .pin(let path, let region):
            let current = state.persistent.marks[path]?.mark
            if current == .pinned { return }
            guard region.pinnedCount < region.capacity else { // R3.3
                effects.append(.showRejection(.pinsFull(capacity: region.capacity)))
                return
            }
            var ms: [StateMutation] = []
            if current == .hidden { ms.append(.clearMark(path)) } // R3.4: restore first
            ms.append(.setMark(MarkRecord(path: path, mark: .pinned, markedAt: now)))
            persist(ms)

        case .unpin(let path):
            guard state.persistent.marks[path]?.mark == .pinned else { return }
            persist([.clearMark(path)])

        case .setRoot(let edge, let path):
            // R5.3: only the root changes; focus, marks, drill paths of the old root stay (keyed by path).
            state.missingRoots.remove(edge)
            if state.lens.edge == edge {
                closeLens()
                state.filterText = ""
                state.lensOpenBeforeFilter = nil
            }
            state.lens.folders[edge] = nil
            persist([.setRoot(edge, path)])

        case .reportRootMissing(let edge, let missing):
            // R6.3: state only; the root is never replaced automatically.
            if missing { state.missingRoots.insert(edge) } else { state.missingRoots.remove(edge) }

        case .copyNode(let path, let kind):
            guard isFull else { return }
            effects.append(.writeNodeToPasteboard(path, kind: kind)) // R8.1: no usage record, panel stays open

        case .paste(let items, let target):
            guard isFull else { return }
            guard !items.isEmpty else {
                effects.append(.showRejection(.clipboardEmpty)) // R8.4
                return
            }
            switch target {
            case .stash:
                for item in items { stashAdd(item.path, item.kind) } // R8.3 + R4.1
            case .folder(let dest):
                // R8.6: a source that is the destination or contains it cannot be copied into it.
                guard !items.contains(where: { $0.path == dest || $0.path.isAncestor(of: dest) }) else {
                    effects.append(.showRejection(.copyIntoItself))
                    return
                }
                let sources = items.map(\.path)
                state.copies.append(CopyJob(sources: sources, destination: dest)) // R8.7
                effects.append(.copyTo(sources: sources, destination: dest)) // R8.2
            }

        case .copyFinished(let dest, let result):
            // Works while the panel is closed: the copy runs in the background (R8.7).
            if let i = state.copies.firstIndex(where: { $0.destination == dest }) { state.copies.remove(at: i) }
            switch result {
            case .success:
                usage(dest, .copyTo) // R8.8
                effects.append(.showNotice(.copiedTo(folderName: (dest.raw as NSString).lastPathComponent)))
            case .failure(let reason):
                effects.append(.showNotice(.copyFailed(reason: reason)))
            }
        }
    }

    // MARK: Pieces

    mutating func openLensState(edge: Edge, folder: NodePath, floor: NodePath, l3: NodePath?) {
        state.lens.isOpen = true
        state.lens.edge = edge
        state.lens.folders[edge] = folder
        state.lens.floor = floor
        state.lens.l3 = l3
    }

    mutating func closeLens() {
        state.lens.isOpen = false
        state.lens.edge = nil
        state.lens.floor = nil
        state.lens.l3 = nil
    }

    /// R5.2: remember where the user stopped inside an L3 star.
    mutating func recordDrill(_ folder: NodePath) {
        guard let l3 = state.lens.l3, folder == l3 || l3.isAncestor(of: folder) else { return }
        persist([.setDrillPath(l3: l3, deep: folder)])
    }

    mutating func restore(_ snap: PanelSnapshot) {
        state.display = .full
        state.lens = snap.lens
        state.filterText = snap.filterText
        state.lensOpenBeforeFilter = snap.lensOpenBeforeFilter
        state.region = snap.region
        state.drag = nil
        effects.append(.restoreFull)
    }

    /// R4.1: max 3, evict oldest; a path appears once, re-adding refreshes addedAt.
    mutating func stashAdd(_ path: NodePath, _ kind: NodeKind) {
        var items = state.persistent.stash.filter { $0.targetPath != path }
        if items.count >= Capacity.stashItems {
            items.removeFirst(items.count - Capacity.stashItems + 1)
        }
        items.append(StashItem(targetPath: path, kind: kind, addedAt: now))
        usage(path, .stash)
        persist([.setStash(items)])
    }

    static func jump(from region: KeyboardRegion, _ dir: Direction) -> KeyboardRegion {
        let target = KeyboardRegion(dir.edge)
        switch region {
        case .center: return target
        case .top: return dir == .up ? region : (dir == .down ? .center : target)
        case .bottom: return dir == .down ? region : (dir == .up ? .center : target)
        case .left: return dir == .left ? region : (dir == .right ? .center : target)
        case .right: return dir == .right ? region : (dir == .left ? .center : target)
        }
    }
}

private extension LensState {
    init(folders: [Edge: NodePath]) {
        self.init()
        self.folders = folders
    }
}
