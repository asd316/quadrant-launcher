import AppKit
import QuadrantCore
import enum QuadrantCore.Edge
import SwiftUI

/// Process-wide state of the drag in progress. The drag source lives in the main panel while the drop zones
/// live in other windows, so both talk through this one object. A zone records the drop before the source's
/// end callback runs.
@MainActor
final class DragCoordinator {
    static let shared = DragCoordinator()

    private(set) var isDragging = false
    private(set) var dropOutcome: DragOutcome?

    func begin() {
        isDragging = true
        dropOutcome = nil
    }

    func recordDrop(on zone: DropZone) {
        switch zone {
        case .stash: dropOutcome = .stash
        case .pinnedShelf(let edge): dropOutcome = .pinnedShelf(edge)
        }
    }

    /// Decides the outcome at session end (R7.3): a recorded zone, cancelled, or another app.
    func finish(operation: NSDragOperation) -> DragOutcome {
        defer {
            isDragging = false
            dropOutcome = nil
        }
        if let dropOutcome { return dropOutcome }
        return operation.isEmpty ? .cancelled : .otherApp
    }
}

/// What every view needs to talk back.
struct UIContext {
    let send: @MainActor (UIEvent) -> Void
    let coordinator: DragCoordinator
    /// Show the icon-only action bar at a point in panel coordinates (top-left origin).
    var presentActions: @MainActor (CGPoint, [NodeAction]) -> Void = { _, _ in }
    var dismissActions: @MainActor () -> Void = {}
    /// Tells the panel which zone an outside drag hovers, for the highlight. `nil` when it leaves.
    var externalHover: @MainActor (DropZone?) -> Void = { _ in }
}

enum ActionIcon {
    case symbol(String)
    /// The real Finder app icon.
    case finder
}

/// One icon button of the action bar. `title` is the tooltip.
struct NodeAction {
    var title: String
    var icon: ActionIcon
    var action: @MainActor () -> Void
}

/// Behavior of one draggable node.
struct InteractionNode {
    var path: NodePath
    var kind: NodeKind
    var context: UIContext
    var onClick: (@MainActor () -> Void)?
    var onDoubleClick: (@MainActor () -> Void)?
    var onHover: (@MainActor (Bool) -> Void)?
    var menu: [NodeAction] = []
    /// Zone an outside (Finder) drop on this node counts for (R7.7).
    var dropZone: DropZone?
    /// Wait out the double-click interval before running `onClick`, so a double click does not also run it.
    var delaysClick = false
}

/// Actions shared by all node types: 复制路径 first, 在 Finder 中显示 after the type-specific ones, `after` last.
@MainActor
func nodeMenu(path: NodePath, context: UIContext, specific: [NodeAction], after: [NodeAction] = []) -> [NodeAction] {
    [NodeAction(title: "复制路径", icon: .symbol("doc.on.doc"), action: { context.send(.copyPath(path)) })]
        + specific
        + [NodeAction(title: "在 Finder 中显示", icon: .finder, action: { context.send(.revealInFinder(path)) })]
        + after
}

/// AppKit overlay that owns click, double click, context menu, hover and drag-out for one node.
struct NodeInteractionOverlay: NSViewRepresentable {
    let node: InteractionNode

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.node = node
        return view
    }

    func updateNSView(_ view: InteractionView, context: Context) {
        view.node = node
    }
}

private final class MenuAction {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
}

final class InteractionView: NSView, NSDraggingSource {
    var node: InteractionNode?
    private var mouseDownEvent: NSEvent?
    private var dragStarted = false
    private var pendingClick: Task<Void, Never>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Return self for any point inside, so views underneath never swallow events.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self,
                userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { node?.onHover?(true) }
    override func mouseExited(with event: NSEvent) { node?.onHover?(false) }

    // MARK: Click and drag

    override func mouseDown(with event: NSEvent) {
        node?.context.dismissActions()
        mouseDownEvent = event
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let down = mouseDownEvent, let node else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard (dx * dx + dy * dy).squareRoot() > 4 else { return }
        dragStarted = true
        let url = URL(fileURLWithPath: node.path.raw)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: node.path.raw)
        icon.size = NSSize(width: 32, height: 32)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: location.x - 16, y: location.y - 16, width: 32, height: 32), contents: icon)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !dragStarted, let node else { return }
        pendingClick?.cancel()
        pendingClick = nil
        if event.clickCount >= 2 {
            node.onDoubleClick?()
        } else if node.delaysClick, node.onDoubleClick != nil, let onClick = node.onClick {
            pendingClick = Task { @MainActor in
                try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
                if !Task.isCancelled { onClick() }
            }
        } else {
            node.onClick?()
        }
    }

    // MARK: Action bar (right click)

    override func rightMouseDown(with event: NSEvent) {
        guard let node, !node.menu.isEmpty else { return }
        let height = window?.contentView?.bounds.height ?? 0
        let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
        node.context.dismissActions()
        node.context.presentActions(point, node.menu)
    }

    // MARK: Outside drops (R7.7)

    private func externalPaths(_ sender: NSDraggingInfo) -> [NodePath] {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map { NodePath($0.path) }
    }

    private var externalZone: DropZone? {
        DragCoordinator.shared.isDragging ? nil : node?.dropZone
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let zone = externalZone, !externalPaths(sender).isEmpty else { return [] }
        node?.context.externalHover(zone)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        externalZone == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { node?.context.externalHover(nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let node, let zone = externalZone else { return false }
        let paths = externalPaths(sender)
        node.context.externalHover(nil)
        guard !paths.isEmpty else { return false }
        node.context.send(.externalDrop(paths, on: zone))
        return true
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        guard let node else { return }
        node.context.coordinator.begin()
        node.context.send(.dragBegan(node.path, node.kind))
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let node else { return }
        let outcome = node.context.coordinator.finish(operation: operation)
        node.context.send(.dragEnded(outcome))
        dragStarted = false
    }
}

/// Drop zone. During the panel's own drag (`DragCoordinator.shared.isDragging`) the zone windows' views
/// record the drop for the source. Otherwise, where `onExternalDrop` is set (the main panel), files dragged
/// in from other apps are reported through it (R7.7). Each instance handles only its own kind, so a drop is
/// never handled twice.
struct ZoneDropTarget: NSViewRepresentable {
    let zone: DropZone
    @Binding var isTargeted: Bool
    var onExternalDrop: (([NodePath]) -> Void)?

    func makeNSView(context: Context) -> ZoneDropView {
        let view = ZoneDropView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ZoneDropView, context: Context) { configure(view) }

    private func configure(_ view: ZoneDropView) {
        view.zone = zone
        view.onTargeted = { isTargeted = $0 }
        view.onExternalDrop = onExternalDrop
    }
}

final class ZoneDropView: NSView {
    var zone: DropZone = .stash
    var onTargeted: ((Bool) -> Void)?
    var onExternalDrop: (([NodePath]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    /// Drop-only view: never takes mouse events, so nodes and background clicks work through it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var isInternalDrag: Bool { DragCoordinator.shared.isDragging }

    /// This instance handles the drag in progress: internal drags in zone windows, outside drags in the panel.
    private var handlesCurrentDrag: Bool { isInternalDrag ? onExternalDrop == nil : onExternalDrop != nil }

    private func paths(_ sender: NSDraggingInfo) -> [NodePath] {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map { NodePath($0.path) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard handlesCurrentDrag, isInternalDrag || !paths(sender).isEmpty else { return [] }
        onTargeted?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        handlesCurrentDrag ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onTargeted?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard handlesCurrentDrag else { return false }
        onTargeted?(false)
        if isInternalDrag {
            DragCoordinator.shared.recordDrop(on: zone)
            return true
        }
        let dropped = paths(sender)
        guard !dropped.isEmpty else { return false }
        onExternalDrop?(dropped)
        return true
    }
}

private struct NodeInteractionModifier: ViewModifier {
    @Environment(\.isStaticRender) private var isStatic
    let node: InteractionNode
    let trailingInset: CGFloat

    func body(content: Content) -> some View {
        if isStatic {
            content
        } else {
            content.overlay(NodeInteractionOverlay(node: node).padding(.trailing, trailingInset))
        }
    }
}

extension View {
    /// Adds the AppKit interaction overlay. `trailingInset` keeps part of the trailing side free for SwiftUI buttons.
    /// Static renders (ImageRenderer) cannot draw AppKit views, so they skip it.
    func nodeInteraction(_ node: InteractionNode, trailingInset: CGFloat = 0) -> some View {
        modifier(NodeInteractionModifier(node: node, trailingInset: trailingInset))
    }
}
