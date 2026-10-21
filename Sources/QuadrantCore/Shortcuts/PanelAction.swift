import Foundation

/// Panel shortcut actions from Design-Principles › Keyboard. Raw values are the keys used in `shortcuts.json`.
public enum PanelAction: String, CaseIterable, Sendable, Hashable {
    case selectPrevious = "select_previous"
    case selectNext = "select_next"
    /// Return: depends on the selected node (focus a branch, open a lens, or copy a file path).
    case activate
    /// ⌘Return: open the selected node with its default app.
    case open
    /// →: enter the selected folder inside the lens.
    case enterFolder = "enter_folder"
    /// ←: back up one level inside the lens.
    case back
    /// ⌘S: put the selected node into the stash.
    case stash
    /// ⌘P: file goes to a pinned slot, folder is pinned.
    case pin
    case jumpUp = "jump_up"
    case jumpDown = "jump_down"
    case jumpLeft = "jump_left"
    case jumpRight = "jump_right"
}

public extension PanelAction {
    /// Default chord from the Design-Principles keyboard table and cross navigation table.
    var defaultChord: KeyChord {
        switch self {
        case .selectPrevious: KeyChord(key: .up)
        case .selectNext: KeyChord(key: .down)
        case .activate: KeyChord(key: .returnKey)
        case .open: KeyChord(modifiers: [.command], key: .returnKey)
        case .enterFolder: KeyChord(key: .right)
        case .back: KeyChord(key: .left)
        case .stash: KeyChord(modifiers: [.command], key: .letter("S"))
        case .pin: KeyChord(modifiers: [.command], key: .letter("P"))
        case .jumpUp: KeyChord(modifiers: [.command], key: .up)
        case .jumpDown: KeyChord(modifiers: [.command], key: .down)
        case .jumpLeft: KeyChord(modifiers: [.command], key: .left)
        case .jumpRight: KeyChord(modifiers: [.command], key: .right)
        }
    }
}
