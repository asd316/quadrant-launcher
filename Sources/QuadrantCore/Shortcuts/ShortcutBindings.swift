import Foundation

/// One problem found while reading the shortcut overrides. `action` is the raw name as written in the file.
public enum ShortcutIssue: Equatable, Sendable {
    /// The file is not a valid `{ "version": 1, "bindings": { … } }` object. All defaults are used.
    case malformedFile
    case unknownAction(String)
    case invalidChord(action: String, chord: String, problem: ChordProblem)
    /// The chord is already used by an earlier action (`with`). The action falls back to its default;
    /// if the default is also taken, the action is left unbound.
    case conflict(action: String, chord: String, with: PanelAction)
}

public struct ShortcutResolution: Equatable, Sendable {
    public let bindings: ShortcutBindings
    public let issues: [ShortcutIssue]

    public init(bindings: ShortcutBindings, issues: [ShortcutIssue]) {
        self.bindings = bindings
        self.issues = issues
    }
}

/// The chord each panel action responds to. An action missing from `chords` is unbound.
public struct ShortcutBindings: Equatable, Sendable {
    public private(set) var chords: [PanelAction: KeyChord]

    private init(chords: [PanelAction: KeyChord]) {
        self.chords = chords
    }

    public static let defaults = ShortcutBindings(
        chords: Dictionary(uniqueKeysWithValues: PanelAction.allCases.map { ($0, $0.defaultChord) })
    )

    public func chord(for action: PanelAction) -> KeyChord? {
        chords[action]
    }

    public func action(for chord: KeyChord) -> PanelAction? {
        chords.first { $0.value == chord }?.key
    }

    /// Applies overrides keyed by raw action name (`"stash": "⌘S"`). Actions are resolved in `PanelAction.allCases`
    /// order, so for a clash the later action is the one that is invalid.
    public static func resolving(overrides: [String: String]) -> ShortcutResolution {
        var issues: [ShortcutIssue] = []
        let known = Set(PanelAction.allCases.map(\.rawValue))
        for name in overrides.keys.filter({ !known.contains($0) }).sorted() {
            issues.append(.unknownAction(name))
        }

        var chords: [PanelAction: KeyChord] = [:]
        var owners: [KeyChord: PanelAction] = [:]

        for action in PanelAction.allCases {
            let fallback = action.defaultChord
            var candidate = fallback

            if let text = overrides[action.rawValue] {
                if let parsed = KeyChord(parsing: text) {
                    if let problem = parsed.customizationProblem {
                        issues.append(.invalidChord(action: action.rawValue, chord: text, problem: problem))
                    } else {
                        candidate = parsed
                    }
                } else {
                    issues.append(.invalidChord(action: action.rawValue, chord: text, problem: .unparseable))
                }
            }

            if let owner = owners[candidate] {
                issues.append(.conflict(action: action.rawValue, chord: candidate.formatted, with: owner))
                guard owners[fallback] == nil else { continue }
                candidate = fallback
            }

            chords[action] = candidate
            owners[candidate] = action
        }

        return ShortcutResolution(bindings: ShortcutBindings(chords: chords), issues: issues)
    }
}
