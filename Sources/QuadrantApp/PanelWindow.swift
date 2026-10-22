import AppKit
import QuadrantCore
import QuadrantUI
import SwiftUI

/// Borderless, non-activating, full-screen panel that can still become key (validated by PanelSpike).
/// Key presses go to `keyHandler` first, so typing works whatever the SwiftUI content has focused.
@MainActor
final class QuadrantPanel: NSPanel {
    var keyHandler: ((KeyInput) -> Bool)?
    var isTyping: ((KeyInput) -> Bool)?
    let textInput = TextInputView()

    init(screenFrame: NSRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = PanelWindowController.panelLevel
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // While the input method is composing, every key (arrows, return, backspace) belongs to it.
            if textInput.hasMarkedText() {
                textInput.inputContext?.handleEvent(event)
                return
            }
            if let input = KeyInput(event: event) {
                if isTyping?(input) == true {
                    if makeFirstResponder(textInput), textInput.inputContext?.handleEvent(event) == true { return }
                } else if keyHandler?(input) == true {
                    return
                }
            }
        }
        super.sendEvent(event)
    }

    // Swallow Esc if it reaches the responder chain unhandled, so AppKit does not beep.
    override func cancelOperation(_ sender: Any?) {}
}

extension KeyInput {
    init?(event: NSEvent) {
        var modifiers: Set<KeyModifier> = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        var key: ChordKey?
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .returnKey
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        default:
            if let c = event.charactersIgnoringModifiers?.uppercased(), c.count == 1, let ch = c.first {
                if ("A"..."Z").contains(ch) { key = .letter(ch) } else if ("0"..."9").contains(ch) { key = .digit(ch) }
            }
        }
        self.init(
            key: key, modifiers: modifiers, text: event.characters ?? "", isBackspace: event.keyCode == 51)
    }
}

/// Root SwiftUI view: redraws `PanelView` whenever the model's render model changes.
struct PanelRoot: View {
    let model: AppModel

    var body: some View {
        PanelView(model: model.render, send: { event in model.handle(event) })
    }
}

/// Owns the panel window and the drop-zone windows shown during a drag.
@MainActor
final class PanelWindowController: PanelWindowControlling {
    /// Just under the menu bar, so the menu bar and status item stay visible and clickable.
    static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
    /// Drop zones sit above the main panel.
    static let zoneLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue)
    static let openDuration: TimeInterval = 0.15
    static let closeDuration: TimeInterval = 0.1
    static let slideDistance: CGFloat = 32

    private let panel: QuadrantPanel
    private let model: AppModel
    private var fullFrame: NSRect
    private var zoneWindows: [NSPanel] = []
    /// Bumped on every show/hide so a late fade-out never hides a panel that was reopened.
    private var generation = 0
    private var isShown = false

    /// Called with true when the panel is shown, false when hidden (status item highlight).
    var onVisibilityChange: ((Bool) -> Void)?

    init(model: AppModel) {
        self.model = model
        let frame = Self.currentFrame()
        fullFrame = frame
        panel = QuadrantPanel(screenFrame: frame)
        let hosting = NSHostingView(rootView: PanelRoot(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.keyHandler = { [weak model] input in model?.handle(key: input) ?? false }
        panel.isTyping = { [weak model] input in model?.isTyping(input) ?? false }
        panel.textInput.onCommit = { [weak model] text in model?.handle(typed: text) }
        hosting.addSubview(panel.textInput)
    }

    private static func currentFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return PanelFrame.frame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func restoreFull() {
        generation += 1
        removeZoneWindows()
        panel.ignoresMouseEvents = false
        fullFrame = Self.currentFrame()
        if isShown {
            // End of a drag: the panel is still ordered in, just transparent.
            panel.setFrame(fullFrame, display: true)
            panel.alphaValue = 1
        } else {
            isShown = true
            let animate = !reduceMotion
            var start = fullFrame
            if animate { start.origin.y += Self.slideDistance }
            panel.setFrame(start, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.openDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                if animate { panel.animator().setFrame(fullFrame, display: true) }
            }
            onVisibilityChange?(true)
        }
        panel.makeKey()
        panel.makeFirstResponder(panel.textInput)
    }

    /// R7.2: the main panel stays ordered in (the drag source view must live) but is invisible and click-through;
    /// one small window per drop zone takes its place. Done after the drag has started, as in the spike.
    func enterHalfHidden() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            showZoneWindows()
        }
    }

    func hide() {
        generation += 1
        let mine = generation
        removeZoneWindows()
        panel.ignoresMouseEvents = false
        guard isShown else { return }
        isShown = false
        onVisibilityChange?(false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.closeDuration
            panel.animator().alphaValue = 0
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.closeDuration + 0.03))
            guard let self, generation == mine else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    // MARK: Drop zones

    private func showZoneWindows() {
        removeZoneWindows()
        let rects = PanelLayout.dropZoneRects(size: fullFrame.size, model: model.render)
        for (zone, rect) in rects {
            let window = NSPanel(
                contentRect: PanelFrame.screenRect(rect, panelFrame: fullFrame),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isFloatingPanel = true
            window.level = Self.zoneLevel
            window.hidesOnDeactivate = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let hosting = NSHostingView(
                rootView: DropZoneView(zone: zone, model: model.render, send: { [model] event in model.handle(event) }))
            hosting.sizingOptions = []
            window.contentView = hosting
            window.orderFrontRegardless()
            zoneWindows.append(window)
        }
    }

    private func removeZoneWindows() {
        for window in zoneWindows { window.orderOut(nil) }
        zoneWindows.removeAll()
    }

    /// Debug aid: draws the panel content into a PNG without screen-recording permission.
    func writeSnapshot(to url: URL) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Invisible text client so the filter accepts input-method text (Chinese pinyin and others).
/// Committed text goes to `onCommit`; the candidate window is placed under the stash.
@MainActor
final class TextInputView: NSView, @preconcurrency NSTextInputClient {
    var onCommit: ((String) -> Void)?
    private var marked = NSAttributedString()

    override var acceptsFirstResponder: Bool { true }

    func insertText(_ string: Any, replacementRange: NSRange) {
        marked = NSAttributedString()
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        onCommit?(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString) ?? NSAttributedString(string: (string as? String) ?? "")
    }

    func unmarkText() { marked = NSAttributedString() }
    func selectedRange() -> NSRange { NSRange(location: marked.length, length: 0) }
    func markedRange() -> NSRange {
        marked.length == 0 ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: marked.length)
    }
    func hasMarkedText() -> Bool { marked.length > 0 }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let frame = window.frame
        return NSRect(x: frame.midX - 200, y: frame.midY - 60, width: 0, height: 20)
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    // Keys the input method does not consume arrive here; the panel already routed them.
    override func doCommand(by selector: Selector) {}
}
