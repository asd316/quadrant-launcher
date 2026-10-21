import Foundation
import Testing
import QuadrantCore
@testable import QuadrantSystem

/// Runs `body` with a fresh temp directory and removes it afterwards.
private func withTempDirectory(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("quadrant-config-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

private func write(_ text: String, named name: String, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func configMissingFileUsesDefaultsWithoutIssue() throws {
    try withTempDirectory { dir in
        let loader = ShortcutsConfigLoader(fileURL: dir.appendingPathComponent("shortcuts.json"))
        let result = loader.load()
        #expect(result.bindings == ShortcutBindings.defaults)
        #expect(result.issues.isEmpty)
    }
}

@Test func configMalformedJSONUsesDefaultsWithOneIssue() throws {
    try withTempDirectory { dir in
        let url = try write("{ \"version\": 1, \"bindings\": ", named: "shortcuts.json", in: dir)
        let result = ShortcutsConfigLoader(fileURL: url).load()
        #expect(result.bindings == ShortcutBindings.defaults)
        #expect(result.issues == [.malformedFile])
    }
}

@Test func configWrongVersionOrShapeIsMalformed() throws {
    try withTempDirectory { dir in
        let wrongVersion = try write(#"{ "version": 2, "bindings": { "stash": "⌘E" } }"#, named: "v2.json", in: dir)
        let noBindings = try write(#"{ "version": 1 }"#, named: "nobind.json", in: dir)
        let arrayRoot = try write(#"[1, 2]"#, named: "array.json", in: dir)
        for url in [wrongVersion, noBindings, arrayRoot] {
            let result = ShortcutsConfigLoader(fileURL: url).load()
            #expect(result.bindings == ShortcutBindings.defaults, "\(url.lastPathComponent)")
            #expect(result.issues == [.malformedFile], "\(url.lastPathComponent)")
        }
    }
}

@Test func configValidOverrideIsApplied() throws {
    try withTempDirectory { dir in
        let url = try write(#"{ "version": 1, "bindings": { "stash": "⌘E", "jump_up": "cmd+shift+up" } }"#,
                            named: "shortcuts.json", in: dir)
        let result = ShortcutsConfigLoader(fileURL: url).load()
        #expect(result.issues.isEmpty)
        #expect(result.bindings.chord(for: .stash)?.formatted == "⌘E")
        #expect(result.bindings.chord(for: .jumpUp)?.formatted == "⇧⌘↑")
        #expect(result.bindings.chord(for: .pin) == PanelAction.pin.defaultChord)
    }
}

@Test func configUnknownActionIsNamedInIssue() throws {
    try withTempDirectory { dir in
        let url = try write(#"{ "version": 1, "bindings": { "fly_away": "⌘F" } }"#, named: "shortcuts.json", in: dir)
        let result = ShortcutsConfigLoader(fileURL: url).load()
        #expect(result.issues == [.unknownAction("fly_away")])
        #expect(result.bindings == ShortcutBindings.defaults)
    }
}

@Test func configInvalidChordUsesDefaultAndNamesAction() throws {
    try withTempDirectory { dir in
        let url = try write(#"{ "version": 1, "bindings": { "stash": "S", "back": "⎋", "pin": "⌘P" } }"#,
                            named: "shortcuts.json", in: dir)
        let result = ShortcutsConfigLoader(fileURL: url).load()
        #expect(result.bindings.chord(for: .stash) == PanelAction.stash.defaultChord)
        #expect(result.bindings.chord(for: .back) == PanelAction.back.defaultChord)
        #expect(result.issues.contains(.invalidChord(action: "stash", chord: "S", problem: .needsModifierOrArrowOrReturn)))
        #expect(result.issues.contains(.invalidChord(action: "back", chord: "⎋", problem: .escapeReserved)))
        #expect(result.issues.count == 2)
    }
}

@Test func configNonStringValueIsInvalidChord() throws {
    try withTempDirectory { dir in
        let url = try write(#"{ "version": 1, "bindings": { "open": 42 } }"#, named: "shortcuts.json", in: dir)
        let result = ShortcutsConfigLoader(fileURL: url).load()
        #expect(result.bindings.chord(for: .open) == PanelAction.open.defaultChord)
        #expect(result.issues.count == 1)
        if case .invalidChord(let action, _, _) = result.issues.first {
            #expect(action == "open")
        } else {
            Issue.record("expected invalidChord for open")
        }
    }
}

@Test func configLoaderNeverWritesFile() throws {
    try withTempDirectory { dir in
        let url = dir.appendingPathComponent("shortcuts.json")
        _ = ShortcutsConfigLoader(fileURL: url).load()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
