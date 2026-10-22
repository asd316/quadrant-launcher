import AppKit
import QuadrantCore
import enum QuadrantCore.Edge
import SwiftUI

/// Shared between every drag source and the stash drop target within one panel.
/// SwiftUI `.onDrag` cannot report the outcome, so sources and the stash talk through this object.
@MainActor
final class DragCoordinator {
    private(set) var isDragging = false
    private(set) var droppedOnStash = false

    func begin() {
        isDragging = true
        droppedOnStash = false
    }

    func markDroppedOnStash() { droppedOnStash = true }

    /// Decides the outcome at session end (R7.3): stash, cancelled, or another app.
    func finish(operation: NSDragOperation) -> DragOutcome {
        defer {
            isDragging = false
            droppedOnStash = false
        }
        if droppedOnStash { return .stash }
        return operation.isEmpty ? .cancelled : .otherApp
    }
}

/// What every view needs to talk back.
struct UIContext {
    let send: @MainActor (UIEvent) -> Void
    let coordinator: DragCoordinator
}

struct NodeMenuItem {
    var title: String
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
    var menu: [NodeMenuItem] = []
}

/// Menu items shared by all node types: 复制路径 first, 在 Finder 中显示 last, type-specific ones between.
@MainActor
func nodeMenu(path: NodePath, context: UIContext, specific: [NodeMenuItem]) -> [NodeMenuItem] {
    [NodeMenuItem(title: "复制路径", action: { context.send(.copyPath(path)) })]
        + specific
        + [NodeMenuItem(title: "在 Finder 中显示", action: { context.send(.revealInFinder(path)) })]
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
        if event.clickCount >= 2 {
            node.onDoubleClick?()
        } else {
            node.onClick?()
        }
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let node, !node.menu.isEmpty else { return nil }
        let menu = NSMenu()
        for entry in node.menu {
            let item = NSMenuItem(title: entry.title, action: #selector(runMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuAction(entry.action)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func runMenuItem(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.run()
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

/// Registers the stash as a drop target and tells the coordinator when something lands on it.
struct StashDropTarget: NSViewRepresentable {
    let coordinator: DragCoordinator

    func makeNSView(context: Context) -> StashDropView {
        let view = StashDropView()
        view.coordinator = coordinator
        return view
    }

    func updateNSView(_ view: StashDropView, context: Context) {
        view.coordinator = coordinator
    }
}

final class StashDropView: NSView {
    var coordinator: DragCoordinator?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        coordinator?.isDragging == true ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        coordinator?.isDragging == true ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard coordinator?.isDragging == true else { return false }
        coordinator?.markDroppedOnStash()
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
