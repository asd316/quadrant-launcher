import AppKit
import Dispatch
import QuadrantCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.live()
    private var windowController: PanelWindowController?
    private var statusItem: NSStatusItem?
    private var hotkey: any GlobalHotkey = AppDelegate.makeHotkey()
    /// Retained for the whole launch; `kill -USR1` shows the panel (used by `Launch Quadrant.command`).
    private var launcherSignal: DispatchSourceSignal?
    /// URL/open events during the first seconds belong to this launch, not to a toggle.
    private var isColdLaunch = true

    /// Seam: return the KeyboardShortcuts-backed hotkey here once full Xcode is available.
    private static func makeHotkey() -> any GlobalHotkey { NoGlobalHotkey() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Double-clicking the app in Finder, or opening a quadrant-launcher:// URL, arrives as an Apple event.
        let manager = NSAppleEventManager.shared()
        manager.setEventHandler(
            self, andSelector: #selector(handleOpenApplication(_:withReplyEvent:)),
            forEventClass: Self.coreEventClass, andEventID: Self.openApplicationEvent)
        manager.setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: Self.internetEventClass, andEventID: Self.getURLEvent)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        let controller = PanelWindowController(model: model)
        windowController = controller
        model.window = controller
        buildStatusItem()
        controller.onVisibilityChange = { [weak self] shown in self?.statusItem?.button?.highlight(shown) }
        hotkey.install { [weak self] in self?.model.togglePanel() }
        installLauncherSignal()
        // Debug aid: QUADRANT_AUTOOPEN=1 opens the panel right after launch (used for screenshots).
        if ProcessInfo.processInfo.environment["QUADRANT_AUTOOPEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.model.togglePanel() }
        }
        // Debug aid: QUADRANT_SNAPSHOT=<file.png> opens the panel, writes it to the file, then quits.
        if let out = ProcessInfo.processInfo.environment["QUADRANT_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.model.togglePanel() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.windowController?.writeSnapshot(to: URL(fileURLWithPath: out))
                NSApp.terminate(nil)
            }
        }
        // A cold launch shows the panel: Finder double-click and Raycast's cold URL both land here.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.model.showPanel()
            self.isColdLaunch = false
        }
    }

    /// Double-clicking the already-running app in Finder / LaunchServices reopen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showPanel()
        return true
    }

    // MARK: Apple events

    private static let coreEventClass = AEEventClass(0x61657674) // 'aevt'
    private static let internetEventClass = AEEventClass(0x4755524C) // 'GURL'
    private static let openApplicationEvent = AEEventID(0x6F617070) // 'oapp'
    private static let getURLEvent = AEEventID(0x4755524C) // 'GURL'
    private static let directObjectKey = AEKeyword(0x2D2D2D2D) // '----'

    @objc private func handleOpenApplication(
        _ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor
    ) {
        if !isColdLaunch { model.showPanel() }
    }

    /// `quadrant-launcher://toggle` is the Raycast bridge: a running app toggles, a cold launch opens.
    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let raw = event.paramDescriptor(forKeyword: Self.directObjectKey)?.stringValue,
              let url = URL(string: raw), url.scheme == "quadrant-launcher"
        else { return }
        if !isColdLaunch { model.togglePanel() }
    }

    // MARK: Launcher

    /// `kill -USR1 <pid>` shows the panel without toggling it. The double-click command uses this when the
    /// app is already running, so a second launch brings the panel forward instead of closing it.
    private func installLauncherSignal() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.model.showPanel() }
        }
        source.resume()
        launcherSignal = source
    }

    // MARK: Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Quadrant Launcher")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true
        if wantsMenu {
            showMenu()
        } else {
            model.togglePanel()
        }
    }

    private func showMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        for (i, edge) in Self.menuEdges.enumerated() {
            let item = NSMenuItem(title: "设置\(Self.name(edge))象限…", action: #selector(chooseRoot(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "清空象限", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, edge) in Self.menuEdges.enumerated() {
            let item = NSMenuItem(title: Self.name(edge), action: #selector(clearRoot(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.isEnabled = model.state.persistent.roots[edge] != nil
            sub.addItem(item)
        }
        clear.submenu = sub
        menu.addItem(clear)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private static let menuEdges: [Edge] = [.top, .bottom, .left, .right]

    private static func name(_ edge: Edge) -> String {
        switch edge {
        case .top: "上"
        case .bottom: "下"
        case .left: "左"
        case .right: "右"
        }
    }

    @objc private func chooseRoot(_ sender: NSMenuItem) {
        let edge = Self.menuEdges[sender.tag]
        // The panel is closed before a modal dialog opens, so it cannot cover it.
        if model.state.display == .full { model.togglePanel() }
        let open = NSOpenPanel()
        open.canChooseFiles = false
        open.canChooseDirectories = true
        open.allowsMultipleSelection = false
        open.prompt = "选择"
        open.message = "选择\(Self.name(edge))象限的常驻文件夹"
        NSApp.activate()
        if open.runModal() == .OK, let url = open.url {
            model.setRoot(edge, to: NodePath(url.path))
        }
    }

    @objc private func clearRoot(_ sender: NSMenuItem) {
        model.setRoot(Self.menuEdges[sender.tag], to: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
