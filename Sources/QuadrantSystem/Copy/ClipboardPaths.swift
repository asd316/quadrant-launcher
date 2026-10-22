import Foundation
import QuadrantCore

/// Turns clipboard contents into paths for paste (R8.4).
public enum ClipboardPaths {
    /// Resolves clipboard contents to existing paths.
    ///
    /// - Parameters:
    ///   - fileURLs: file URLs from the pasteboard. Non-file URLs are ignored.
    ///   - text: one absolute path per line. Lines starting with `~` expand to the home folder.
    ///     Blank lines, other lines and surrounding whitespace are ignored.
    ///   - exists: decides whether a path exists. Paths it rejects are dropped.
    /// - Returns: existing paths, first occurrence kept, file URLs first and then text lines.
    ///   Kind is read from FileManager (`fileExists(atPath:isDirectory:)`, which follows symlinks).
    public static func resolve(
        fileURLs: [URL],
        text: String?,
        exists: (String) -> Bool
    ) -> [(NodePath, NodeKind)] {
        var candidates = fileURLs.filter(\.isFileURL).map { NodePath($0.path) }
        if let text {
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else { continue }
                candidates.append(NodePath(trimmed))
            }
        }
        var seen = Set<NodePath>()
        var result: [(NodePath, NodeKind)] = []
        for path in candidates where seen.insert(path).inserted {
            guard exists(path.raw) else { continue }
            result.append((path, kind(of: path)))
        }
        return result
    }

    private static func kind(of path: NodePath) -> NodeKind {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path.raw, isDirectory: &isDirectory)
        return isDirectory.boolValue ? .folder : .file
    }
}
