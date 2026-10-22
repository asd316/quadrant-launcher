import Foundation
import QuadrantCore

/// Errors from `FileCopier`. Shown to the user by the panel (R8.6, R8.7).
public enum FileCopyError: Error, Equatable, CustomStringConvertible {
    /// R8.6: the destination is a source itself or lies inside one. Nothing was copied.
    case destinationInsideSource(NodePath)
    case destinationNotFolder(NodePath)
    /// R8.7: copying `item` failed. Its partial copy is removed; earlier copies are kept.
    case copyFailed(item: NodePath, reason: String)

    public var description: String {
        switch self {
        case .destinationInsideSource(let path): "Cannot copy into itself: \(path.raw)"
        case .destinationNotFolder(let path): "Destination is not a folder: \(path.raw)"
        case .copyFailed(let item, let reason): "Could not copy \(item.name): \(reason)"
        }
    }
}

/// Copies files and folders into a folder (R8.2, R8.5–R8.7).
/// This is the only System write to the user's disk, and it only creates new items (R6.4).
/// Never overwrites: a taken name gets a Finder-style suffix instead.
public struct FileCopier: Sendable {
    public init() {}

    /// Copies each source into `destination` and returns the created paths, in source order.
    /// `progress` receives the fraction of items finished (0...1) after each item.
    public func copy(
        sources: [NodePath],
        into destination: NodePath,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [NodePath] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.raw, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileCopyError.destinationNotFolder(destination)
        }
        // Check every source before copying anything (R8.6).
        let resolvedDestination = Self.canonical(destination)
        for source in sources {
            let resolvedSource = Self.canonical(source)
            if resolvedSource == resolvedDestination || resolvedSource.isAncestor(of: resolvedDestination) {
                throw FileCopyError.destinationInsideSource(destination)
            }
        }

        var created: [NodePath] = []
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            created.append(try Self.copyOne(source, into: destination))
            progress?(Double(index + 1) / Double(sources.count))
        }
        return created
    }

    // MARK: - Naming (R8.5)

    /// Returns `name` if it is free, otherwise the first free Finder-style variant:
    /// `报告.pdf` → `报告 2.pdf` → `报告 3.pdf`; `资料` → `资料 2`.
    static func uniqueName(for name: String, kind: NodeKind, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        let (stem, ext) = splitExtension(name, kind: kind)
        var number = 2
        while true {
            let candidate = ext.map { "\(stem) \(number).\($0)" } ?? "\(stem) \(number)"
            if !isTaken(candidate) { return candidate }
            number += 1
        }
    }

    /// Splits `报告.pdf` into ("报告", "pdf"). Folders, dotfiles such as `.env`, and names ending in "." have no extension.
    static func splitExtension(_ name: String, kind: NodeKind) -> (stem: String, ext: String?) {
        guard kind == .file, let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return (name, nil)
        }
        let ext = name[name.index(after: dot)...]
        guard !ext.isEmpty else { return (name, nil) }
        return (String(name[..<dot]), String(ext))
    }

    // MARK: - Copying

    private static func copyOne(_ source: NodePath, into destination: NodePath) throws -> NodePath {
        let kind: NodeKind = isDirectory(source.raw) ? .folder : .file
        let name = uniqueName(for: source.name, kind: kind) { itemExists(destination.appending($0).raw) }
        let target = destination.appending(name)
        do {
            try FileManager.default.copyItem(atPath: source.raw, toPath: target.raw)
        } catch {
            // Only remove what this call created. A file that appeared after the name was chosen is not ours.
            if (error as NSError).code != NSFileWriteFileExistsError {
                removePartialCopy(target.raw)
            }
            throw FileCopyError.copyFailed(item: source, reason: error.localizedDescription)
        }
        return target
    }

    /// Removes a partial copy. Copied folders keep the source's permissions, so a locked
    /// folder is made writable first. Source files are never touched.
    private static func removePartialCopy(_ path: String) {
        makeWritableRecursively(path)
        try? FileManager.default.removeItem(atPath: path)
    }

    private static func makeWritableRecursively(_ path: String) {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeDirectory else { return }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        for child in (try? fm.contentsOfDirectory(atPath: path)) ?? [] {
            makeWritableRecursively((path as NSString).appendingPathComponent(child))
        }
    }

    // MARK: - Helpers

    /// Symlinks are resolved so that a destination reached through a link still counts as inside its source.
    private static func canonical(_ path: NodePath) -> NodePath {
        NodePath(URL(fileURLWithPath: path.raw).resolvingSymlinksInPath().path)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// True for broken symlinks too, which `fileExists` would miss.
    private static func itemExists(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)) != nil
    }
}
