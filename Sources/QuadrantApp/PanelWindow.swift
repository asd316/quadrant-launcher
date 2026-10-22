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
        level = .screenSaver
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

/// Owns the panel window. Shrink and restore follow the drag behaviour confirmed in PanelSpike.
@MainActor
final class PanelWindowController: PanelWindowControlling {
    /// Stash rectangle around the screen center while a drag runs (R7.2).
    static let stashSize = NSSize(width: 360, height: 220)

    private let panel: QuadrantPanel
    private var fullFrame: NSRect

    init(model: AppModel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        fullFrame = screen.frame
        panel = QuadrantPanel(screenFrame: fullFrame)
        let hosting = NSHostingView(rootView: PanelRoot(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.keyHandler = { [weak model] input in model?.handle(key: input) ?? false }
        panel.isTyping = { [weak model] input in model?.isTyping(input) ?? false }
        panel.textInput.onCommit = { [weak model] text in model?.handle(typed: text) }
        hosting.addSubview(panel.textInput)
    }

    func restoreFull() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        fullFrame = screen.frame
        panel.setFrame(fullFrame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(panel.textInput)
    }

    func enterHalfHidden() {
        // After the drag has started: resizing inside the drag-begin callback can end the session.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let size = Self.stashSize
            panel.setFrame(
                NSRect(
                    x: fullFrame.midX - size.width / 2, y: fullFrame.midY - size.height / 2,
                    width: size.width, height: size.height),
                display: true)
        }
    }

    func hide() {
        panel.orderOut(nil)
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
