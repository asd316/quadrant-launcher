import Foundation

/// Seam for the global summon hotkey. The chosen library (KeyboardShortcuts) needs full Xcode, so for now
/// the app installs `NoGlobalHotkey`. Replace the instance in `AppDelegate.makeHotkey()` when it is available.
@MainActor
protocol GlobalHotkey {
    /// Registers the hotkey; `onPress` toggles the panel.
    func install(onPress: @escaping @MainActor () -> Void)
}

@MainActor
struct NoGlobalHotkey: GlobalHotkey {
    func install(onPress: @escaping @MainActor () -> Void) {}
}
