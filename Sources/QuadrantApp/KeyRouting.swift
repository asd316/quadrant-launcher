import Foundation
import QuadrantCore
import QuadrantUI

/// A key press reduced to what routing needs. Built from `NSEvent` in the panel; plain data here so it can be tested.
struct KeyInput: Equatable {
    var key: ChordKey?
    var modifiers: Set<KeyModifier>
    /// Characters the key types, empty for arrows and function keys.
    var text: String
    var isBackspace: Bool = false

    init(key: ChordKey? = nil, modifiers: Set<KeyModifier> = [], text: String = "", isBackspace: Bool = false) {
        self.key = key
        self.modifiers = modifiers
        self.text = text
        self.isBackspace = isBackspace
    }
}

enum KeyCommand: Equatable {
    case escape
    case panel(PanelAction)
    /// ⌘C, fixed (R8.1).
    case copyNode
    /// ⌘V, fixed (R8.2).
    case paste
    case backspace
    case text(String)
}

enum KeyRouter {
    /// Esc is fixed, then the configurable chords, then ⌘C / ⌘V, then Backspace, then typing. `nil` = not ours.
    static func route(_ input: KeyInput, bindings: ShortcutBindings) -> KeyCommand? {
        if input.key == .escape { return .escape }
        if input.isBackspace { return .backspace }
        if let key = input.key {
            let chord = KeyChord(modifiers: input.modifiers, key: key)
            if let action = bindings.action(for: chord) { return .panel(action) }
            if chord == KeyChord(modifiers: [.command], key: .letter("C")) { return .copyNode }
            if chord == KeyChord(modifiers: [.command], key: .letter("V")) { return .paste }
        }
        if input.modifiers.isDisjoint(with: [.command, .control]) {
            let typed = input.text.filter(isTypable)
            if !typed.isEmpty { return .text(typed) }
        }
        return nil
    }

    /// Letters, digits, punctuation, CJK. Not control codes, and not the private-use codes arrows and F-keys send.
    private static func isTypable(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned, .lineSeparator, .paragraphSeparator: false
            default: true
            }
        }
    }
}

/// What key resolution may read.
struct KeyContext {
    var mapping: MappingContext
    var selection: NodePath?
    /// Called only for ⌘V, so the pasteboard is read lazily.
    var pasteItems: () -> [PasteItem]

    var state: PanelState { mapping.state }
    var model: PanelRenderModel { mapping.model }
    var selectedNode: SelectedNode? { selection.flatMap { Selection.find($0, in: model) } }
}

enum KeyResolver {
    static func commands(for command: KeyCommand, in ctx: KeyContext) -> [AppCommand] {
        let state = ctx.state
        switch command {
        case .escape:
            return [.intent(.escape)]
        case .text(let s):
            return [.intent(.setFilter(state.filterText + s))]
        case .backspace:
            guard !state.filterText.isEmpty else { return [] }
            return [.intent(.setFilter(String(state.filterText.dropLast())))]
        case .copyNode:
            guard let node = ctx.selectedNode else { return [] }
            return [.intent(.copyNode(node.path, kind: node.kind))]
        case .paste:
            let target = Selection.pasteTarget(for: ctx.selectedNode)
            return [.intent(.paste(items: ctx.pasteItems(), target: target))]
        case .panel(let action):
            return panel(action, in: ctx)
        }
    }

    private static func panel(_ action: PanelAction, in ctx: KeyContext) -> [AppCommand] {
        switch action {
        case .selectPrevious:
            return [.select(Selection.move(from: ctx.selection, by: -1, in: ctx.model))]
        case .selectNext:
            return [.select(Selection.move(from: ctx.selection, by: 1, in: ctx.model))]
        case .activate:
            return activate(in: ctx)
        case .open:
            guard let node = ctx.selectedNode else { return [] }
            return node.kind == .folder ? [.openFolderInFinder(node.path)] : [.intent(.open(node.path))]
        case .enterFolder:
            return enter(in: ctx)
        case .back:
            guard ctx.state.lens.isOpen, ctx.state.filterText.isEmpty else { return [] }
            return [.intent(.lensBack)]
        case .stash:
            guard let node = ctx.selectedNode else { return [] }
            return [.intent(.stashAdd(node.path, kind: node.kind))]
        case .pin:
            return pin(in: ctx)
        case .jumpUp: return jump(.up)
        case .jumpDown: return jump(.down)
        case .jumpLeft: return jump(.left)
        case .jumpRight: return jump(.right)
        }
    }

    private static func jump(_ direction: Direction) -> [AppCommand] {
        [.intent(.crossNavigate(direction)), .select(nil)]
    }

    /// ↩: file → copy path, folder in the lens → enter, branch → focus, star → open its lens.
    private static func activate(in ctx: KeyContext) -> [AppCommand] {
        guard let node = ctx.selectedNode else { return [] }
        switch node.role {
        case .branch(let edge):
            return [.intent(.focusBranch(edge, branch: node.path))]
        case .star(let edge):
            return [.intent(.clickStar(edge, star: node.path, existence: ctx.mapping.exists))]
        case .lensRow:
            return node.kind == .file ? [.intent(.copyPath(node.path))] : enterFolder(node, in: ctx)
        case .floating, .pinnedSlot, .stash:
            return [.intent(.copyPath(node.path))]
        }
    }

    /// →: go into the selected folder. Branches and stars have no deeper level in place, so they act like ↩.
    private static func enter(in ctx: KeyContext) -> [AppCommand] {
        guard let node = ctx.selectedNode, node.kind == .folder else { return [] }
        switch node.role {
        case .lensRow: return enterFolder(node, in: ctx)
        case .branch, .star: return activate(in: ctx)
        case .floating, .pinnedSlot, .stash: return []
        }
    }

    private static func enterFolder(_ node: SelectedNode, in ctx: KeyContext) -> [AppCommand] {
        var mapping = ctx.mapping
        // The render model, not Core state, knows a filter lens row's edge.
        mapping.model = ctx.model
        return EventMapper.enterFolder(node.path, in: mapping)
    }

    /// ⌘P: a file goes to a pinned slot of the current quadrant, a folder is pinned in place.
    private static func pin(in ctx: KeyContext) -> [AppCommand] {
        guard let node = ctx.selectedNode, let edge = Selection.edge(of: node, in: ctx.model) else { return [] }
        switch node.kind {
        case .file:
            return [.intent(.pinSlot(edge, node.path, kind: .file))]
        case .folder:
            return EventMapper.commands(for: .pinFolder(edge, node.path), in: ctx.mapping)
        }
    }
}
