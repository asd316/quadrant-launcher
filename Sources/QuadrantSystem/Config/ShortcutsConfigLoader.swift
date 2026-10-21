import Foundation
import QuadrantCore

/// Reads `shortcuts.json` (Data-Model › Configured). Read-only: never writes or creates the file.
public struct ShortcutsConfigLoader: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = ShortcutsConfigLoader.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/QuadrantLauncher/shortcuts.json")
    }

    /// Missing file: defaults, no issue. Unreadable or malformed file: defaults plus `.malformedFile`.
    /// Bad entries: that action uses its default, with one issue per entry.
    public func load() -> ShortcutResolution {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ShortcutResolution(bindings: .defaults, issues: [])
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return ShortcutResolution(bindings: .defaults, issues: [.malformedFile])
        }
        return Self.decode(data)
    }

    static func decode(_ data: Data) -> ShortcutResolution {
        let malformed = ShortcutResolution(bindings: .defaults, issues: [.malformedFile])
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            root["version"] as? Int == 1,
            let entries = root["bindings"] as? [String: Any]
        else {
            return malformed
        }

        var overrides: [String: String] = [:]
        for (name, value) in entries {
            // A non-string value is reported as an invalid chord with its printed form.
            overrides[name] = (value as? String) ?? String(describing: value)
        }
        return ShortcutBindings.resolving(overrides: overrides)
    }
}
