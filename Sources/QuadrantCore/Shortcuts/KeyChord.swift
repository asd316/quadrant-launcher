import Foundation

public enum KeyModifier: String, CaseIterable, Sendable, Hashable {
    case control
    case option
    case shift
    case command

    /// Symbol used in display strings.
    public var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    static func parse(_ token: String) -> KeyModifier? {
        switch token.lowercased() {
        case "⌃", "ctrl", "control": .control
        case "⌥", "opt", "option", "alt": .option
        case "⇧", "shift": .shift
        case "⌘", "cmd", "command": .command
        default: nil
        }
    }
}

/// The non-modifier part of a chord. Letters are stored uppercase.
public enum ChordKey: Hashable, Sendable {
    case letter(Character)
    case digit(Character)
    case up
    case down
    case left
    case right
    case returnKey
    case escape

    /// Arrow keys and Return: the only keys that may be bound without a modifier.
    public var isArrowOrReturn: Bool {
        switch self {
        case .up, .down, .left, .right, .returnKey: true
        case .letter, .digit, .escape: false
        }
    }

    var symbol: String {
        switch self {
        case .letter(let c), .digit(let c): String(c)
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .returnKey: "↩"
        case .escape: "⎋"
        }
    }

    static func parse(_ token: String) -> ChordKey? {
        if token.count == 1, let c = token.uppercased().first {
            if ("A"..."Z").contains(c) { return .letter(c) }
            if ("0"..."9").contains(c) { return .digit(c) }
            switch c {
            case "↑": return .up
            case "↓": return .down
            case "←": return .left
            case "→": return .right
            case "↩": return .returnKey
            case "⎋": return .escape
            default: return nil
            }
        }
        switch token.lowercased() {
        case "up": return .up
        case "down": return .down
        case "left": return .left
        case "right": return .right
        case "return": return .returnKey
        case "esc", "escape": return .escape
        default: return nil
        }
    }
}

/// Why a chord cannot be used as a custom panel shortcut.
public enum ChordProblem: Equatable, Sendable {
    case unparseable
    case escapeReserved
    case needsModifierOrArrowOrReturn
}

/// A key combination such as `⌘S`, `⌘↩`, `→` or `⌘↑`.
public struct KeyChord: Hashable, Sendable, CustomStringConvertible {
    public let modifiers: Set<KeyModifier>
    public let key: ChordKey

    public init(modifiers: Set<KeyModifier> = [], key: ChordKey) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Parses symbol form (`⌘S`, `⇧↑`) or plus form (`cmd+s`, `shift+up`). Does not check customization rules;
    /// use `customizationProblem` for that.
    public init?(parsing text: String) {
        let compact = text.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return nil }

        var modifiers: Set<KeyModifier> = []
        let keyToken: String

        if compact.contains("+") {
            var parts = compact.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            guard let last = parts.popLast(), !last.isEmpty else { return nil }
            for part in parts {
                guard let modifier = KeyModifier.parse(part) else { return nil }
                modifiers.insert(modifier)
            }
            keyToken = last
        } else {
            var rest = Substring(compact)
            while let first = rest.first, let modifier = KeyModifier.parse(String(first)) {
                modifiers.insert(modifier)
                rest = rest.dropFirst()
            }
            keyToken = String(rest)
        }

        guard let key = ChordKey.parse(keyToken) else { return nil }
        self.modifiers = modifiers
        self.key = key
    }

    /// Display form in macOS menu order: ⌃⌥⇧⌘ then the key, e.g. `⌘↩`, `→`, `⌘S`.
    public var formatted: String {
        KeyModifier.allCases.filter { modifiers.contains($0) }.map(\.symbol).joined() + key.symbol
    }

    public var description: String { formatted }

    /// Customization rules: Esc is never bindable, and a chord needs a modifier
    /// unless it is an arrow or Return key.
    public var customizationProblem: ChordProblem? {
        if key == .escape { return .escapeReserved }
        if modifiers.isEmpty && !key.isArrowOrReturn { return .needsModifierOrArrowOrReturn }
        return nil
    }
}
