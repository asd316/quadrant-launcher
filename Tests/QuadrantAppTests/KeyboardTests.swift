import QuadrantCore
import QuadrantUI
import Testing

@testable import QuadrantApp

@Suite struct KeyboardTests {
    private let defaults = ShortcutBindings.defaults

    private func route(_ key: ChordKey? = nil, _ mods: Set<KeyModifier> = [], text: String = "", backspace: Bool = false) -> KeyCommand? {
        KeyRouter.route(KeyInput(key: key, modifiers: mods, text: text, isBackspace: backspace), bindings: defaults)
    }

    @Test func routing() {
        #expect(route(.escape) == .escape)
        #expect(route(.up) == .panel(.selectPrevious))
        #expect(route(.down) == .panel(.selectNext))
        #expect(route(.returnKey) == .panel(.activate))
        #expect(route(.returnKey, [.command]) == .panel(.open))
        #expect(route(.right) == .panel(.enterFolder))
        #expect(route(.left) == .panel(.back))
        #expect(route(.letter("S"), [.command], text: "s") == .panel(.stash))
        #expect(route(.letter("P"), [.command], text: "p") == .panel(.pin))
        #expect(route(.up, [.command]) == .panel(.jumpUp))
        #expect(route(.letter("C"), [.command], text: "c") == .copyNode)
        #expect(route(.letter("V"), [.command], text: "v") == .paste)
        #expect(route(backspace: true) == .backspace)
    }

    @Test func plainCharactersTypeIntoFilter() {
        #expect(route(.letter("A"), text: "a") == .text("a"))
        #expect(route(.letter("A"), [.shift], text: "A") == .text("A"))
        #expect(route(nil, text: "报") == .text("报"))
        // Unbound command chords are not typing.
        #expect(route(.letter("Z"), [.command], text: "z") == nil)
        // Arrow keys carry private-use characters; they must never type.
        #expect(route(.up, [.shift], text: "\u{F700}") == nil)
        #expect(route(nil, text: "\r") == nil)
    }

    @Test func customBindingIsHonoured() {
        let custom = ShortcutBindings.resolving(overrides: ["stash": "⌘D"]).bindings
        let input = KeyInput(key: .letter("D"), modifiers: [.command], text: "d")
        #expect(KeyRouter.route(input, bindings: custom) == .panel(.stash))
        let old = KeyInput(key: .letter("S"), modifiers: [.command], text: "s")
        #expect(KeyRouter.route(old, bindings: custom) == nil)
    }

    // MARK: Resolution

    private func ctx(
        _ state: PanelState, selection: NodePath?, items: [PasteItem] = [], cache: [NodePath: [FolderNode]] = [:]
    ) -> KeyContext {
        KeyContext(mapping: mapping(state, cache: cache), selection: selection, pasteItems: { items })
    }

    private func resolve(_ command: KeyCommand, _ c: KeyContext) -> [String] {
        describe(KeyResolver.commands(for: command, in: c))
    }

    @Test func typingAndBackspaceEditFilterText() {
        var state = baseState()
        #expect(resolve(.text("a"), ctx(state, selection: nil)) == ["setFilter(a)"])
        state.filterText = "ab"
        #expect(resolve(.text("c"), ctx(state, selection: nil)) == ["setFilter(abc)"])
        #expect(resolve(.backspace, ctx(state, selection: nil)) == ["setFilter(a)"])
        state.filterText = ""
        #expect(resolve(.backspace, ctx(state, selection: nil)) == [])
    }

    @Test func arrowsWalkTheRegionThenClamp() {
        var state = baseState()
        state.region = .top
        let c0 = ctx(state, selection: nil)
        let order = Selection.order(in: c0.model)
        #expect(order.first == np("/r/top/Alpha") || order.first == np("/r/top/Beta"))
        let first = resolve(.panel(.selectNext), c0)
        #expect(first == ["select(\(order[0].raw))"])
        let last = resolve(.panel(.selectNext), ctx(state, selection: order.last))
        #expect(last == ["select(\(order.last!.raw))"])
        #expect(resolve(.panel(.selectPrevious), c0) == ["select(\(order.last!.raw))"])
    }

    @Test func activateDependsOnWhatIsSelected() {
        let state = baseState()
        #expect(resolve(.panel(.activate), ctx(state, selection: np("/r/top/Beta"))) == ["focusBranch(top,/r/top/Beta)"])
        #expect(resolve(.panel(.activate), ctx(state, selection: np("/r/top/Alpha/Docs"))) == ["drillCloud(top,/r/top/Alpha/Docs)"])
        #expect(resolve(.panel(.activate), ctx(state, selection: np("/r/top/Alpha/note.txt"))) == ["copyPath(/r/top/Alpha/note.txt)"])
        #expect(resolve(.panel(.activate), ctx(state, selection: nil)) == [])

        var lens = baseState()
        lens.lens.isOpen = true
        lens.lens.edge = .top
        lens.lens.folders[.top] = np("/r/top/Alpha")
        #expect(resolve(.panel(.activate), ctx(lens, selection: np("/r/top/Alpha/Docs"))) == ["lensEnter(/r/top/Alpha/Docs)"])
        #expect(resolve(.panel(.activate), ctx(lens, selection: np("/r/top/Alpha/note.txt"))) == ["copyPath(/r/top/Alpha/note.txt)"])
    }

    @Test func fileStarActivatesAsFile() {
        var state = baseState()
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top")
        #expect(Selection.find(np("/r/top/readme.txt"), in: ctx(state, selection: nil).model)?.kind == .file)
        #expect(
            resolve(.panel(.activate), ctx(state, selection: np("/r/top/readme.txt")))
                == ["copyPath(/r/top/readme.txt)"])
        let item = PasteItem(np("/tmp/x.txt"), kind: .file)
        #expect(
            resolve(.paste, ctx(state, selection: np("/r/top/readme.txt"), items: [item]))
                == ["paste([\"/tmp/x.txt\"],stash)"])
    }

    @Test func filterRowFolderOpensItsLensAfterClearingFilter() {
        var state = baseState()
        state.filterText = "docs"
        state.lens.isOpen = true
        #expect(resolve(.panel(.activate), ctx(state, selection: np("/r/top/Alpha/Docs")))
            == ["setFilter()", "openLens(top,/r/top/Alpha/Docs)"])
    }

    @Test func openStashBackAndJump() {
        var state = baseState()
        #expect(resolve(.panel(.open), ctx(state, selection: np("/r/top/Alpha/note.txt"))) == ["open(/r/top/Alpha/note.txt)"])
        #expect(resolve(.panel(.stash), ctx(state, selection: np("/r/top/Alpha/note.txt"))) == ["stashAdd(/r/top/Alpha/note.txt)"])
        #expect(resolve(.panel(.back), ctx(state, selection: nil)) == [])
        state.lens.isOpen = true
        state.lens.edge = .top
        #expect(resolve(.panel(.back), ctx(state, selection: nil)) == ["lensBack"])
        #expect(resolve(.panel(.jumpLeft), ctx(state, selection: nil)) == ["cross(left)", "select(nil)"])
        #expect(resolve(.escape, ctx(state, selection: nil)) == ["escape"])
    }

    @Test func pinSendsFilesToSlotsAndPinsFolders() {
        let state = baseState()
        #expect(resolve(.panel(.pin), ctx(state, selection: np("/r/top/Alpha/note.txt"))) == ["pinSlot(top,/r/top/Alpha/note.txt)"])
        #expect(resolve(.panel(.pin), ctx(state, selection: np("/r/top/Beta"))) == ["pin(/r/top/Beta,0/4)"])
    }

    @Test func copyNodeUsesSelection() {
        let state = baseState()
        #expect(resolve(.copyNode, ctx(state, selection: np("/r/top/Beta"))) == ["copyNode(/r/top/Beta)"])
        #expect(resolve(.copyNode, ctx(state, selection: nil)) == [])
    }

    // MARK: Paste target (R8.2–R8.4)

    @Test func pasteTargetIsSelectedFolderElseStash() {
        let state = baseState()
        let item = PasteItem(np("/tmp/x.txt"), kind: .file)
        let toFolder = resolve(.paste, ctx(state, selection: np("/r/top/Beta"), items: [item]))
        #expect(toFolder == ["paste([\"/tmp/x.txt\"],folder(/r/top/Beta))"])
        let toStar = resolve(.paste, ctx(state, selection: np("/r/top/Alpha/Docs"), items: [item]))
        #expect(toStar == ["paste([\"/tmp/x.txt\"],folder(/r/top/Alpha/Docs))"])
        let fileSel = resolve(.paste, ctx(state, selection: np("/r/top/Alpha/note.txt"), items: [item]))
        #expect(fileSel == ["paste([\"/tmp/x.txt\"],stash)"])
        let none = resolve(.paste, ctx(state, selection: nil, items: [item]))
        #expect(none == ["paste([\"/tmp/x.txt\"],stash)"])
        let empty = resolve(.paste, ctx(state, selection: nil))
        #expect(empty == ["paste([],stash)"])
    }

    @Test func pasteTargetFolderInLens() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha")
        let c = ctx(state, selection: np("/r/top/Alpha/Docs"))
        #expect(Selection.pasteTarget(for: c.selectedNode) == .folder(np("/r/top/Alpha/Docs")))
    }
}
