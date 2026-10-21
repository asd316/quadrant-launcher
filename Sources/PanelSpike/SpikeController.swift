import AppKit

@MainActor
final class SpikeController: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var statusItem: NSStatusItem?
    private var panel: SpikePanel?
    private var root: SpikeRootView?
    private var fullFrame = NSRect.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sampleURL = Self.createSampleFile()
        buildStatusItem()
        buildPanel(fileURL: sampleURL)
        log("launched; sample file \(sampleURL.path); click the menu bar item")
        if ProcessInfo.processInfo.environment["PANELSPIKE_AUTOOPEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel() }
        }
    }

    // MARK: Setup

    private static func createSampleFile() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/PanelSpike", isDirectory: true)
        let url = dir.appendingPathComponent("sample.txt")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "PanelSpike sample file\n".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("sample file error: \(error)\n".utf8))
        }
        return url
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "PS"
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Panel", action: #selector(showPanel), keyEquivalent: "")
        show.target = self
        let quit = NSMenuItem(title: "Quit PanelSpike", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(show)
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func buildPanel(fileURL: URL) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        fullFrame = screen.frame
        let panel = SpikePanel(screenFrame: fullFrame)
        let root = SpikeRootView(fileURL: fileURL)
        root.textField.delegate = self
        root.stash.onDrop = { [weak root] in root?.fileRow.dropRecorded = true }
        root.fileRow.onDragBegan = { [weak self] in self?.dragBegan() }
        root.fileRow.onDragEnded = { [weak self] outcome in self?.dragEnded(outcome) }
        panel.onEscape = { [weak self] in self?.closePanel(reason: "Esc") }
        panel.contentView = root
        self.panel = panel
        self.root = root
    }

    // MARK: Panel

    @objc private func showPanel() {
        guard let panel, let root else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        fullFrame = screen.frame
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        root.stashOnly = false
        panel.setFrame(fullFrame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(root.textField)
        log("opened. frontmost before=\(front) after=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") appActive=\(NSApp.isActive) panelKey=\(panel.isKeyWindow)")
    }

    private func closePanel(reason: String) {
        panel?.orderOut(nil)
        log("closed (\(reason)). frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Drag

    private func dragBegan() {
        guard let panel, let root else { return }
        log("drag began: hiding all but stash")
        root.stashOnly = true
        let size = NSSize(width: 320, height: 200)
        panel.setFrame(
            NSRect(x: fullFrame.midX - size.width / 2, y: fullFrame.midY - size.height / 2, width: size.width, height: size.height),
            display: true
        )
    }

    private func dragEnded(_ outcome: DragOutcome) {
        guard let panel, let root else { return }
        switch outcome {
        case .stash:
            log("DRAG RESULT: dropped on STASH box")
        case .otherApp:
            log("DRAG RESULT: dropped into ANOTHER APP")
        case .cancelled:
            log("DRAG RESULT: CANCELLED")
        }
        if outcome == .otherApp {
            closePanel(reason: "dropped elsewhere")
        } else {
            root.stashOnly = false
            panel.setFrame(fullFrame, display: true)
            panel.makeKey()
            panel.makeFirstResponder(root.textField)
            log("panel restored; key=\(panel.isKeyWindow)")
        }
    }

    // MARK: Typing

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            log("typed: \"\(field.stringValue)\"")
        }
    }

    private func log(_ message: String) {
        FileHandle.standardOutput.write(Data("[PanelSpike] \(message)\n".utf8))
    }
}
