import AppKit

/// Lays out everything relative to the bounds center so the stash box stays
/// at the exact screen center in both full and stash-only mode.
@MainActor
final class SpikeRootView: NSView {
    let textField = NSTextField(string: "")
    let fileRow: FileRowView
    let stash = StashView()
    private let hint = NSTextField(labelWithString: "Type here. Esc closes. Drag the file row out.")
    var stashOnly = false {
        didSet { applyMode() }
    }

    init(fileURL: URL) {
        fileRow = FileRowView(fileURL: fileURL)
        super.init(frame: .zero)
        wantsLayer = true
        textField.placeholderString = "typing test"
        textField.font = .systemFont(ofSize: 22)
        hint.textColor = .white
        hint.alignment = .center
        for v in [hint, textField, fileRow, stash] as [NSView] { addSubview(v) }
        applyMode()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func applyMode() {
        layer?.backgroundColor = stashOnly ? NSColor.clear.cgColor : NSColor.black.withAlphaComponent(0.6).cgColor
        hint.isHidden = stashOnly
        textField.isHidden = stashOnly
        fileRow.isHidden = stashOnly
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let cx = bounds.midX, cy = bounds.midY
        stash.frame = NSRect(x: cx - 140, y: cy - 70, width: 280, height: 140)
        textField.frame = NSRect(x: cx - 200, y: cy + 110, width: 400, height: 32)
        hint.frame = NSRect(x: cx - 250, y: cy + 160, width: 500, height: 20)
        fileRow.frame = NSRect(x: cx - 200, y: cy + 210, width: 400, height: 44)
    }
}

/// Central drop box: the only thing visible during a drag.
@MainActor
final class StashView: NSView {
    var onDrop: (() -> Void)?
    /// Set only while a drag-in from another app is in progress.
    var onExternalDrop: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.85).cgColor
        layer?.cornerRadius = 16
        registerForDraggedTypes([.fileURL])
        let label = NSTextField(labelWithString: "STASH (drop here)")
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 18)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        spikeLog("stash draggingEntered")
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        spikeLog("stash received: \(urls.map(\.path))")
        if let external = onExternalDrop {
            onExternalDrop = nil
            external()
        } else {
            onDrop?()
        }
        return true
    }
}

enum DragOutcome: String {
    case stash = "STASH"
    case otherApp = "OTHER-APP"
    case cancelled = "CANCELLED"
}

/// Draggable row for a real file, using AppKit's NSDraggingSource.
@MainActor
final class FileRowView: NSView, NSDraggingSource {
    let fileURL: URL
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((DragOutcome) -> Void)?
    var dropRecorded = false
    private var mouseDownPoint: NSPoint?
    private var dragStarted = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.cornerRadius = 8
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: fileURL.path))
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: fileURL.lastPathComponent + "  (drag me)")
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(name)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The icon and label subviews would otherwise take the mouse events, so the row never sees a drag.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) && !isHidden ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragStarted = false
        spikeLog("row mouseDown")
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let start = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        dragStarted = true
        dropRecorded = false

        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let local = convert(p, from: nil)
        item.setDraggingFrame(
            NSRect(x: local.x - 24, y: local.y - 24, width: 48, height: 48),
            contents: NSWorkspace.shared.icon(forFile: fileURL.path)
        )
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        spikeLog("drag session started")
        // Change the window only after AppKit has taken over the drag.
        DispatchQueue.main.async { [weak self] in self?.onDragBegan?() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Receiver decides copy vs move; we only ever offer copy/generic (R6.4).
        [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let outcome: DragOutcome
        if dropRecorded {
            outcome = .stash
        } else if operation.isEmpty {
            outcome = .cancelled
        } else {
            outcome = .otherApp
        }
        spikeLog("op rawValue=\(operation.rawValue) at=\(screenPoint)")
        onDragEnded?(outcome)
    }
}

func spikeLog(_ message: String) {
    FileHandle.standardOutput.write(Data("[PanelSpike] \(message)\n".utf8))
}

/// Covers the menu bar button so a drag coming from another app can open the panel (drag-in, K3).
/// Clicks are passed on to the button so its menu still works.
@MainActor
final class StatusDropView: NSView {
    var onDragEntered: (() -> Void)?
    weak var button: NSStatusBarButton?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) { button?.performClick(nil) }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        spikeLog("menu bar button draggingEntered: opening stash")
        onDragEntered?()
        return .copy
    }
}
