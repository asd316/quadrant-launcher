import AppKit
import Foundation
import Observation
import QuadrantCore
import QuadrantSystem
import QuadrantUI

/// Owns the Core state and everything around it: scans, usage log, store, effects, selection.
/// Every change ends in `rebuild()`, which projects Core state into the `PanelRenderModel` the UI draws.
@MainActor
@Observable
final class AppModel {
    /// What the panel draws. The only property views observe.
    private(set) var render = PanelRenderModel()

    @ObservationIgnored private(set) var state = PanelState()
    @ObservationIgnored private(set) var selection: NodePath?
    @ObservationIgnored private var snapshots: [Edge: FolderSnapshot] = [:]
    @ObservationIgnored private var starCapacity: [Edge: Int] = [:]
    @ObservationIgnored private var childrenCache: [NodePath: [FolderNode]] = [:]
    @ObservationIgnored private var usageEvents: [UsageEvent] = []
    @ObservationIgnored private var usage = UsageIndex.empty
    @ObservationIgnored private var message: String?
    @ObservationIgnored private var copyProgress: Double?
    @ObservationIgnored private var pendingNotices: [String]

    @ObservationIgnored private let store: (any StateStore & UsageLog)?
    @ObservationIgnored private let folderSource: any FolderSource
    @ObservationIgnored private let copier: FileCopier
    @ObservationIgnored private let bindings: ShortcutBindings
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let messageDuration: Duration

    @ObservationIgnored weak var window: (any PanelWindowControlling)?
    @ObservationIgnored private var watchedRoots: [Edge: NodePath] = [:]
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var scanTasks: [Edge: Task<Void, Never>] = [:]
    @ObservationIgnored private var messageTask: Task<Void, Never>?

    init(
        store: (any StateStore & UsageLog)?,
        folderSource: any FolderSource = FileSystemFolderSource(),
        copier: FileCopier = FileCopier(),
        bindings: ShortcutBindings = .defaults,
        startupNotices: [String] = [],
        messageDuration: Duration = .milliseconds(2500),
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.store = store
        self.folderSource = folderSource
        self.copier = copier
        self.bindings = bindings
        self.pendingNotices = startupNotices
        self.messageDuration = messageDuration
        self.clock = clock
    }

    /// Opens the real store and shortcut config in the app's own Application Support folder.
    static func live() -> AppModel {
        var notices: [String] = []
        var store: SQLiteStore?
        do {
            let opened = try SQLiteStore()
            store = opened
            if opened.didResetAfterCorruption { notices.append(Messages.stateReset) }
        } catch {
            notices.append(Messages.storeSaveFailed)
        }
        let resolution = ShortcutsConfigLoader().load()
        if let text = Messages.text(for: resolution.issues) { notices.append(text) }
        return AppModel(store: store, bindings: resolution.bindings, startupNotices: notices)
    }

    // MARK: Start

    /// Loads persisted state, seeds first-run roots, starts scanning and watching.
    func start() {
        if let store {
            do {
                state.persistent = try store.load()
                usageEvents = try store.all()
            } catch {
                pendingNotices.append(Messages.storeSaveFailed)
            }
        }
        usage = UsageIndex(events: usageEvents, asOf: clock())
        if state.persistent.roots.isEmpty {
            let seed = FirstRunSeed.roots(
                home: NSHomeDirectory(), exists: { FileManager.default.fileExists(atPath: $0) })
            for edge in Edge.allCases {
                if let path = seed[edge] { dispatch(.setRoot(edge, path), rebuild: false) }
            }
        }
        syncRoots()
        rebuild()
    }

    // MARK: Entry points

    /// Left click on the status item and the global hotkey seam.
    func togglePanel() {
        switch state.display {
        case .closed:
            dispatch(.summon)
        case .full:
            closePanel()
        case .halfHidden:
            break
        }
    }

    /// Esc steps back one level at a time (through Core, so state stays consistent); repeat until closed.
    func closePanel() {
        for _ in 0..<4 where state.display == .full { dispatch(.escape, rebuild: false) }
        rebuild()
    }

    func setRoot(_ edge: Edge, to path: NodePath?) {
        dispatch(.setRoot(edge, path))
    }

    func handle(_ event: UIEvent) {
        perform(EventMapper.commands(for: event, in: mappingContext()))
    }

    /// Returns true when the key was ours. The panel passes everything else on.
    func handle(key input: KeyInput) -> Bool {
        guard state.display != .closed else { return false }
        guard let command = KeyRouter.route(input, bindings: bindings) else { return false }
        guard state.display == .full else { return true }
        let ctx = KeyContext(
            mapping: mappingContext(), selection: selection, pasteItems: { PasteboardWriter.readPasteItems() })
        perform(KeyResolver.commands(for: command, in: ctx))
        return true
    }

    /// Plain typing goes through the input method (IME) instead of `handle(key:)`, so Chinese can compose.
    func isTyping(_ input: KeyInput) -> Bool {
        guard state.display == .full, case .text = KeyRouter.route(input, bindings: bindings) else { return false }
        return true
    }

    /// Text committed by the input method: appended to the filter (L6).
    func handle(typed text: String) {
        guard state.display == .full, !text.isEmpty else { return }
        let ctx = KeyContext(
            mapping: mappingContext(), selection: selection, pasteItems: { PasteboardWriter.readPasteItems() })
        perform(KeyResolver.commands(for: .text(text), in: ctx))
    }

    private func mappingContext() -> MappingContext {
        MappingContext(
            state: state, model: render, starCapacity: starCapacity,
            exists: PathExistence { FileManager.default.fileExists(atPath: $0.raw) })
    }

    private func perform(_ commands: [AppCommand]) {
        for command in commands {
            switch command {
            case .intent(let intent): dispatch(intent, rebuild: false)
            case .select(let path): selection = path
            case .reveal(let path): NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.raw)])
            case .starCapacity(let edge, let count):
                starCapacity[edge] = max(0, count)
            case .dismissPanel: closePanel()
            }
        }
        rebuild()
    }

    // MARK: Core loop

    func dispatch(_ intent: Intent, rebuild shouldRebuild: Bool = true) {
        let (next, effects) = reduce(state, intent, now: clock())
        state = next
        for effect in effects { execute(effect) }
        syncRoots()
        if shouldRebuild { rebuild() }
    }

    func rebuild() {
        var model = build()
        if let sel = selection, Selection.find(sel, in: model) == nil { selection = nil }
        if selection == nil, !state.filterText.isEmpty { selection = model.lens?.rows.first?.path }
        if model.keyboardSelection != selection {
            model = build()
        }
        render = model
    }

    private func build() -> PanelRenderModel {
        RenderModelBuilder.build(RenderInputs(
            state: state, snapshots: snapshots, starCapacity: starCapacity, childrenCache: childrenCache,
            usage: usage, now: usage.asOf,
            exists: PathExistence { FileManager.default.fileExists(atPath: $0.raw) },
            selection: selection, copyProgress: copyProgress, message: message))
    }

    // MARK: Effects

    private func execute(_ effect: Effect) {
        switch effect {
        case .persist(let mutations):
            do { try store?.apply(mutations) } catch { showMessage(Messages.storeSaveFailed) }
        case .recordUsage(let event):
            usageEvents.append(event)
            do { try store?.append(event) } catch { showMessage(Messages.storeSaveFailed) }
            usage = UsageIndex(events: usageEvents, asOf: clock())
        case .copyToPasteboard(let path):
            PasteboardWriter.writePath(path)
        case .writeNodeToPasteboard(let path, _):
            PasteboardWriter.writeNode(path)
        case .openWithDefaultApp(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path.raw))
        case .loadChildren(let folder):
            reloadChildren(folder)
        case .showRejection(let rejection):
            showMessage(Messages.text(for: rejection))
        case .showNotice(let notice):
            showMessage(Messages.text(for: notice))
        case .copyTo(let sources, let destination):
            startCopy(sources: sources, destination: destination)
        case .closePanel:
            selection = nil
            window?.hide()
        case .enterHalfHidden:
            window?.enterHalfHidden()
        case .restoreFull:
            window?.restoreFull()
            if !pendingNotices.isEmpty {
                showMessage(pendingNotices.joined(separator: "；"))
                pendingNotices = []
            }
        }
    }

    private func showMessage(_ text: String) {
        message = text
        messageTask?.cancel()
        let duration = messageDuration
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.message = nil
            self.rebuild()
        }
        rebuild()
    }

    private func startCopy(sources: [NodePath], destination: NodePath) {
        copyProgress = 0
        let copier = copier
        Task { [weak self] in
            let owner = self
            let result: CopyResult
            do {
                let created = try await copier.copy(sources: sources, into: destination) { fraction in
                    Task { @MainActor in
                        owner?.copyProgress = fraction
                        owner?.rebuild()
                    }
                }
                result = .success(copiedNames: created.map(\.name))
            } catch let error as FileCopyError {
                if case .copyFailed(_, let reason) = error {
                    result = .failure(reason: reason)
                } else {
                    result = .failure(reason: error.description)
                }
            } catch {
                result = .failure(reason: error.localizedDescription)
            }
            guard let self else { return }
            self.copyProgress = nil
            self.dispatch(.copyFinished(destination: destination, result: result))
        }
    }

    // MARK: Scanning and watching

    /// Rescans and re-watches when the set of roots changed (setRoot, first run, load).
    private func syncRoots() {
        let roots = state.persistent.roots
        guard roots != watchedRoots else { return }
        let old = watchedRoots
        watchedRoots = roots
        for edge in Edge.allCases where roots[edge] != old[edge] {
            snapshots[edge] = nil
            scanTasks[edge]?.cancel()
            if roots[edge] != nil { rescan(edge) }
        }
        restartWatching()
    }

    private func rescan(_ edge: Edge) {
        guard let root = state.persistent.roots[edge] else { return }
        scanTasks[edge]?.cancel()
        let source = folderSource
        scanTasks[edge] = Task { [weak self] in
            let snapshot = try? await source.snapshot(root: root)
            guard !Task.isCancelled, let self, self.state.persistent.roots[edge] == root else { return }
            self.snapshots[edge] = snapshot
            if snapshot == nil {
                self.dispatch(.reportRootMissing(edge, true))
            } else if self.state.missingRoots.contains(edge) {
                self.dispatch(.reportRootMissing(edge, false))
            } else {
                self.rebuild()
            }
        }
    }

    private func restartWatching() {
        watchTask?.cancel()
        let roots = Array(watchedRoots.values)
        guard !roots.isEmpty else { return }
        let stream = folderSource.changes(under: roots)
        watchTask = Task { [weak self] in
            for await changed in stream {
                guard !Task.isCancelled, let self else { return }
                self.handleChanges(changed)
            }
        }
    }

    private func handleChanges(_ changed: Set<NodePath>) {
        for (edge, root) in watchedRoots
        where changed.contains(where: { $0 == root || root.isAncestor(of: $0) || $0.isAncestor(of: root) }) {
            rescan(edge)
        }
        for folder in childrenCache.keys
        where changed.contains(where: { $0 == folder || $0.parent == folder || folder.isAncestor(of: $0) }) {
            reloadChildren(folder)
        }
    }

    /// Reads one folder for the lens. A failed read counts as empty so the lens stops showing 「正在读取…」.
    private func reloadChildren(_ folder: NodePath) {
        let source = folderSource
        Task { [weak self] in
            let children = (try? await source.children(of: folder)) ?? []
            guard let self else { return }
            self.childrenCache[folder] = children
            self.rebuild()
        }
    }
}
