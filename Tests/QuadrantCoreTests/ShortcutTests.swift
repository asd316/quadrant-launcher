import Testing
@testable import QuadrantCore

// Keyboard: default table, cross navigation, customization limits. Esc is R7.5.

@Test func shortcutDefaultsMatchDesignTable() {
    let bindings = ShortcutBindings.defaults
    let expected: [PanelAction: String] = [
        .selectPrevious: "↑", .selectNext: "↓", .activate: "↩", .open: "⌘↩",
        .enterFolder: "→", .back: "←", .stash: "⌘S", .pin: "⌘P",
        .jumpUp: "⌘↑", .jumpDown: "⌘↓", .jumpLeft: "⌘←", .jumpRight: "⌘→",
    ]
    #expect(PanelAction.allCases.count == expected.count)
    for action in PanelAction.allCases {
        #expect(bindings.chord(for: action)?.formatted == expected[action], "\(action)")
    }
}

@Test func shortcutActionRawValuesAreSnakeCase() {
    #expect(PanelAction.selectPrevious.rawValue == "select_previous")
    #expect(PanelAction.jumpRight.rawValue == "jump_right")
    #expect(PanelAction.activate.rawValue == "activate")
}

@Test func shortcutParsesSymbolAndPlusForms() {
    #expect(KeyChord(parsing: "⌘S") == KeyChord(modifiers: [.command], key: .letter("S")))
    #expect(KeyChord(parsing: "⌘↩") == KeyChord(modifiers: [.command], key: .returnKey))
    #expect(KeyChord(parsing: "→") == KeyChord(key: .right))
    #expect(KeyChord(parsing: "⌘↑") == KeyChord(modifiers: [.command], key: .up))
    #expect(KeyChord(parsing: "cmd+shift+s") == KeyChord(modifiers: [.command, .shift], key: .letter("S")))
    #expect(KeyChord(parsing: "s") == KeyChord(key: .letter("S")))
}

@Test func shortcutFormatsInMacOrder() {
    let chord = KeyChord(modifiers: [.command, .control, .shift, .option], key: .letter("K"))
    #expect(chord.formatted == "⌃⌥⇧⌘K")
    #expect(KeyChord(parsing: chord.formatted) == chord)
}

@Test func shortcutRejectsUnparseableText() {
    #expect(KeyChord(parsing: "") == nil)
    #expect(KeyChord(parsing: "⌘") == nil)
    #expect(KeyChord(parsing: "SS") == nil)
    #expect(KeyChord(parsing: "foo+s") == nil)
    #expect(KeyChord(parsing: "⌘⌘⌘") == nil)
}

@Test func shortcutNeedsModifierOrArrowOrReturn() {
    #expect(KeyChord(parsing: "S")?.customizationProblem == .needsModifierOrArrowOrReturn)
    #expect(KeyChord(parsing: "5")?.customizationProblem == .needsModifierOrArrowOrReturn)
    #expect(KeyChord(parsing: "⇧S")?.customizationProblem == nil)
    #expect(KeyChord(parsing: "↩")?.customizationProblem == nil)
    #expect(KeyChord(parsing: "←")?.customizationProblem == nil)
}

@Test func r7_5_escapeIsNeverBindable() {
    #expect(KeyChord(parsing: "⎋")?.customizationProblem == .escapeReserved)
    #expect(KeyChord(parsing: "⌘⎋")?.customizationProblem == .escapeReserved)
    #expect(KeyChord(parsing: "esc")?.customizationProblem == .escapeReserved)
}

@Test func shortcutResolvingWithoutOverridesIsDefaults() {
    let result = ShortcutBindings.resolving(overrides: [:])
    #expect(result.bindings == ShortcutBindings.defaults)
    #expect(result.issues.isEmpty)
}

@Test func shortcutOverrideReplacesDefault() {
    let result = ShortcutBindings.resolving(overrides: ["stash": "⌘E"])
    #expect(result.bindings.chord(for: .stash)?.formatted == "⌘E")
    #expect(result.bindings.action(for: KeyChord(modifiers: [.command], key: .letter("E"))) == .stash)
    #expect(result.issues.isEmpty)
}

@Test func shortcutUnknownActionIsReportedAndIgnored() {
    let result = ShortcutBindings.resolving(overrides: ["explode": "⌘X"])
    #expect(result.issues == [.unknownAction("explode")])
    #expect(result.bindings == ShortcutBindings.defaults)
}

@Test func shortcutInvalidChordFallsBackToDefaultAndNamesAction() {
    let result = ShortcutBindings.resolving(overrides: ["pin": "P", "open": "⎋"])
    #expect(result.bindings.chord(for: .pin) == PanelAction.pin.defaultChord)
    #expect(result.bindings.chord(for: .open) == PanelAction.open.defaultChord)
    #expect(result.issues.contains(.invalidChord(action: "pin", chord: "P", problem: .needsModifierOrArrowOrReturn)))
    #expect(result.issues.contains(.invalidChord(action: "open", chord: "⎋", problem: .escapeReserved)))
    #expect(result.issues.count == 2)
}

@Test func shortcutLaterDuplicateIsInvalid() {
    // stash comes before pin in PanelAction order, so pin is the later one and falls back to ⌘P.
    let result = ShortcutBindings.resolving(overrides: ["pin": "⌘S"])
    #expect(result.bindings.chord(for: .stash)?.formatted == "⌘S")
    #expect(result.bindings.chord(for: .pin)?.formatted == "⌘P")
    #expect(result.issues == [.conflict(action: "pin", chord: "⌘S", with: .stash)])
}

@Test func shortcutDuplicateWithTakenDefaultLeavesActionUnbound() {
    // stash takes ⌘P (pin's default), so pin has neither its custom nor its default chord.
    let result = ShortcutBindings.resolving(overrides: ["stash": "⌘P"])
    #expect(result.bindings.chord(for: .stash)?.formatted == "⌘P")
    #expect(result.bindings.chord(for: .pin) == nil)
    #expect(result.issues == [.conflict(action: "pin", chord: "⌘P", with: .stash)])
}

@Test func shortcutActionForChordReturnsOwner() {
    let bindings = ShortcutBindings.defaults
    #expect(bindings.action(for: KeyChord(key: .right)) == .enterFolder)
    #expect(bindings.action(for: KeyChord(modifiers: [.option], key: .right)) == nil)
}
